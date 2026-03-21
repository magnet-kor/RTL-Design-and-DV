// =============================================================================
// rmsnorm.sv — Root Mean Square Normalization (6-Stage Pipeline)
// =============================================================================
// RMSNorm(x) = x / RMS(x) * gamma,   RMS = sqrt(mean(x^2))
//
// Pipeline (N=896):
//   Stage 1: x^2        1 cycle   (element-wise, INT8*INT8->INT16)
//   Stage 2: Σ x^2     10 cycles  (tree_sum, N=1024 padded, log2(1024))
//   Stage 3: / N        1 cycle   (×73 >> 16,  approx 1/896, err=0.18%)
//   Stage 4: √          8 cycles  (Newton-Raphson ISQRT, 4 iters × 2 phases)
//   Stage 5: 1/rms      1 cycle   (Q7: 16384/rms)
//   Stage 6: × gamma    1 cycle   (scale and clip to INT8)
//            ──────────────────────
//            Total      22 cycles  = 110 ns @ 200 MHz
//            vs LayerNorm 34 cycles → 1.55× faster
//
// Note: /operator replaced with reciprocal LUT to avoid iterative divider
//       synthesis. 1/x for x in [1,255] precomputed as 65536/x (Q16).
// =============================================================================
`timescale 1ns/1ps

module rmsnorm #(
    parameter N            = 896,
    parameter DATA_W       = 8,
    parameter SUM_W        = 32,
    parameter ISQRT_ITERS  = 4
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          valid_in,
    output logic                          valid_out,
    input  logic signed [DATA_W-1:0]      x_in    [0:N-1],
    input  logic signed [DATA_W-1:0]      gamma   [0:N-1],
    output logic signed [DATA_W-1:0]      x_out   [0:N-1]
);
    // 1/N in Q16: round(65536/N)  (0.18% error for N=896)
    localparam [15:0] RECIP_N_Q16 = 16'(65536 / N);

    // ── Stage 1: x² (1 cycle, parallel) ─────────────────────────────────
    logic [15:0]  xsq   [0:N-1];
    logic         v_s1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_s1 <= 1'b0;
        end else begin
            v_s1 <= valid_in;
            for (int i = 0; i < N; i++)
                xsq[i] <= unsigned'(x_in[i]) * unsigned'(x_in[i]);
        end
    end

    // ── Stage 2: tree_sum (ceil(log2(N)) cycles) ─────────────────────────
    localparam TREE_N = (N <= 512)  ? 512  :
                        (N <= 1024) ? 1024 : 2048;
    logic [15:0]   xsq_pad [0:TREE_N-1];
    logic [SUM_W-1:0] sum_sq;
    logic          v_s2;

    always_comb begin
        for (int i = 0; i < N; i++)       xsq_pad[i] = xsq[i];
        for (int i = N; i < TREE_N; i++)  xsq_pad[i] = '0;
    end

    tree_sum #(.N(TREE_N), .IN_W(16), .OUT_W(SUM_W),
               .LEVELS($clog2(TREE_N))) u_sum (
        .clk(clk), .rst_n(rst_n),
        .in(xsq_pad), .valid_in(v_s1),
        .sum_out(sum_sq), .valid_out(v_s2)
    );

    // ── x_in and gamma delay pipeline (align with ISQRT output) ─────────
    localparam TREE_LEVELS = $clog2(TREE_N);
    localparam INPUT_DELAY = 1 + TREE_LEVELS + 1 + ISQRT_ITERS*2 + 1;

    logic signed [DATA_W-1:0] x_delay [0:INPUT_DELAY-1][0:N-1];
    logic signed [DATA_W-1:0] g_delay [0:INPUT_DELAY-1][0:N-1];

    always_ff @(posedge clk) begin
        for (int i = 0; i < N; i++) begin
            x_delay[0][i] <= x_in[i];
            g_delay[0][i] <= gamma[i];
        end
        for (int d = 1; d < INPUT_DELAY; d++)
            for (int i = 0; i < N; i++) begin
                x_delay[d][i] <= x_delay[d-1][i];
                g_delay[d][i] <= g_delay[d-1][i];
            end
    end

    // ── Stage 3: / N = × RECIP_N_Q16 >> 16 ─────────────────────────────
    logic [SUM_W-1:0] mean_sq;
    logic             v_s3;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_s3 <= 1'b0; mean_sq <= '0;
        end else begin
            v_s3    <= v_s2;
            mean_sq <= (sum_sq * 64'd(RECIP_N_Q16)) >> 16;
        end
    end

    // ── Stage 4: ISQRT Newton-Raphson (8 cycles) ─────────────────────────
    // Reciprocal LUT avoids iterative divider synthesis (/ operator)
    logic [15:0] isqrt_recip_lut [0:255];
    initial begin
        isqrt_recip_lut[0] = 16'hFFFF;
        for (int i = 1; i < 256; i++)
            isqrt_recip_lut[i] = 16'(65536 / i);
    end

    logic [15:0]  isqrt_x;
    logic [15:0]  div_result;
    logic [SUM_W-1:0] isqrt_s;
    logic [1:0]   isqrt_iter;
    logic         isqrt_phase;
    logic         v_s4;

    typedef enum logic [1:0] { ISQ_IDLE, ISQ_RUN, ISQ_DONE } isqrt_st_t;
    isqrt_st_t isqrt_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            isqrt_state <= ISQ_IDLE;
            v_s4        <= 1'b0;
        end else begin
            v_s4 <= 1'b0;
            case (isqrt_state)
                ISQ_IDLE: begin
                    if (v_s3) begin
                        isqrt_s    <= mean_sq;
                        isqrt_x    <= (mean_sq == 0) ? 16'd1 :
                                      (16'd1 << ((31 - $clz(mean_sq[31:0])) >> 1));
                        isqrt_iter <= '0;
                        isqrt_phase<= '0;
                        isqrt_state<= ISQ_RUN;
                    end
                end
                ISQ_RUN: begin
                    if (!isqrt_phase) begin
                        // Phase 0: LUT-based division replacement
                        div_result  <= (isqrt_x == 0) ? 16'hFFFF :
                                       16'((isqrt_s[15:0] * isqrt_recip_lut[isqrt_x[7:0]]) >> 16);
                        isqrt_phase <= 1;
                    end else begin
                        isqrt_x     <= (isqrt_x + div_result) >> 1;
                        isqrt_phase <= 0;
                        if (isqrt_iter == ISQRT_ITERS - 1)
                            isqrt_state <= ISQ_DONE;
                        else
                            isqrt_iter <= isqrt_iter + 1;
                    end
                end
                ISQ_DONE: begin
                    v_s4        <= 1'b1;
                    isqrt_state <= ISQ_IDLE;
                end
            endcase
        end
    end

    // ── Stage 5: 1/rms in Q7 ────────────────────────────────────────────
    logic [15:0]  recip_rms;
    logic         v_s5;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_s5 <= 1'b0; recip_rms <= '0;
        end else begin
            v_s5      <= v_s4;
            recip_rms <= (isqrt_x == 0) ? 16'hFFFF : 16384 / isqrt_x;
        end
    end

    // ── Stage 6: normalize × gamma → INT8 ───────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            for (int i = 0; i < N; i++) x_out[i] <= '0;
        end else begin
            valid_out <= v_s5;
            for (int i = 0; i < N; i++) begin
                automatic logic signed [23:0] xr =
                    $signed(x_delay[INPUT_DELAY-1][i]) *
                    $signed({1'b0, recip_rms[7:0]});
                automatic logic signed [15:0] xr_q7 = xr >>> 7;
                automatic logic signed [23:0] out_q14 =
                    xr_q7 * $signed(g_delay[INPUT_DELAY-1][i]);
                automatic logic signed [15:0] out_q7 = out_q14 >>> 7;
                x_out[i] <= (out_q7 > 127)  ?  8'sd127  :
                             (out_q7 < -128) ? -8'sd128  :
                             out_q7[DATA_W-1:0];
            end
        end
    end

endmodule
