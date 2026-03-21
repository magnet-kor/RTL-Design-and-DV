// =============================================================================
// softmax.sv — Fixed-Point Safe Softmax (6-Stage Pipeline)
// =============================================================================
// Implements softmax(x) = exp(x - max) / Σ exp(x - max)
// Subtraction of max prevents overflow for any INT8 input range.
//
// Pipeline stages and latencies (N=8):
//   Stage 1: tree_max        3 cycles   (log2 N)
//   Stage 2: x - max         1 cycle
//   Stage 3: EXP LUT         1 cycle    (512 B ROM)
//   Stage 4: tree_sum        3 cycles   (log2 N)
//   Stage 5: recip_nr        9 cycles   (Newton-Raphson, 2-stage pipeline)
//   Stage 6: multiply        1 cycle
//            ──────────────────────────
//            Total          18 cycles   = 90 ns @ 200 MHz
//
// Data alignment:
//   - scores delayed 3 cycles to match max_out (Stage 1 latency)
//   - exp_vals delayed 8 cycles to match recip (Stage 3→5 gap)
// =============================================================================
`timescale 1ns/1ps

module softmax #(
    parameter N      = 8,
    parameter DATA_W = 8,
    parameter EXP_W  = 16,
    parameter SUM_W  = 32,
    parameter REC_W  = 16,
    parameter OUT_W  = 8
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic signed [DATA_W-1:0]      scores   [0:N-1],
    input  logic                          valid_in,
    output logic [OUT_W-1:0]              probs    [0:N-1],
    output logic                          valid_out
);
    // ── Stage 1: tree_max ────────────────────────────────────────────────
    logic signed [DATA_W-1:0]  max_val;
    logic                       max_valid;

    tree_max #(.N(N), .DATA_W(DATA_W)) u_max (
        .clk(clk), .rst_n(rst_n),
        .in(scores), .valid_in(valid_in),
        .max_out(max_val), .valid_out(max_valid)
    );

    // ── scores delay buffer (align with max_out) ─────────────────────────
    localparam MAX_LAT = $clog2(N);   // = 3 for N=8
    logic signed [DATA_W-1:0] scores_d [0:MAX_LAT-1][0:N-1];

    always_ff @(posedge clk) begin
        for (int i = 0; i < N; i++) scores_d[0][i] <= scores[i];
        for (int d = 1; d < MAX_LAT; d++)
            for (int i = 0; i < N; i++) scores_d[d][i] <= scores_d[d-1][i];
    end

    // ── Stage 2: subtract max, convert to LUT index ───────────────────────
    logic [DATA_W-1:0]          lut_idx  [0:N-1];
    logic                       sub_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sub_valid <= 1'b0;
        end else begin
            sub_valid <= max_valid;
            for (int i = 0; i < N; i++) begin
                automatic logic signed [DATA_W:0] shifted =
                    $signed(scores_d[MAX_LAT-1][i]) - $signed(max_val);
                // shifted in [-255, 0]; LUT index = shifted + 255
                lut_idx[i] <= (shifted < -255) ? 8'd0 :
                              (shifted > 0)    ? 8'd255 :
                              8'(shifted + 255);
            end
        end
    end

    // ── Stage 3: EXP LUT (N parallel ROM instances) ──────────────────────
    logic [EXP_W-1:0]  exp_vals [0:N-1];
    logic               exp_valid_int;

    generate
        for (genvar i = 0; i < N; i++) begin : gen_exp
            exp_lut #(.ADDR_W(8), .DATA_W(EXP_W)) u_exp (
                .clk(clk), .rst_n(rst_n),
                .addr(lut_idx[i]), .valid_in(sub_valid),
                .data(exp_vals[i]), .valid_out()
            );
        end
    endgenerate
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) exp_valid_int <= 1'b0;
        else        exp_valid_int <= sub_valid;   // 1-cycle latency
    end

    // ── Stage 4: tree_sum ────────────────────────────────────────────────
    localparam TREE_N = (N <= 8) ? 8 : ((N <= 16) ? 16 : 1024);
    logic [EXP_W-1:0]  exp_padded [0:TREE_N-1];
    logic [SUM_W-1:0]  exp_sum;
    logic               sum_valid;

    always_comb begin
        for (int i = 0; i < N; i++)    exp_padded[i] = exp_vals[i];
        for (int i = N; i < TREE_N; i++) exp_padded[i] = '0;
    end

    tree_sum #(.N(TREE_N), .IN_W(EXP_W), .OUT_W(SUM_W),
               .LEVELS($clog2(TREE_N))) u_sum (
        .clk(clk), .rst_n(rst_n),
        .in(exp_padded), .valid_in(exp_valid_int),
        .sum_out(exp_sum), .valid_out(sum_valid)
    );

    // ── Stage 5: recip_nr ────────────────────────────────────────────────
    logic [REC_W-1:0]  recip;
    logic               rec_valid;

    recip_nr #(.IN_W(SUM_W), .OUT_W(REC_W), .ITERS(4)) u_recip (
        .clk(clk), .rst_n(rst_n),
        .s_in(exp_sum), .valid_in(sum_valid),
        .recip_out(recip), .valid_out(rec_valid)
    );

    // ── exp_vals delay buffer (align with recip) ──────────────────────────
    // Delay: from exp_valid_int to rec_valid = 3(sum)+9(recip) = 12 cycles
    localparam EXP_DELAY = $clog2(TREE_N) + 9;   // = 3+9=12 for N=8
    logic [EXP_W-1:0] exp_delay [0:EXP_DELAY-1][0:N-1];

    always_ff @(posedge clk) begin
        for (int i = 0; i < N; i++) exp_delay[0][i] <= exp_vals[i];
        for (int d = 1; d < EXP_DELAY; d++)
            for (int i = 0; i < N; i++) exp_delay[d][i] <= exp_delay[d-1][i];
    end

    // ── Stage 6: multiply exp_delayed * recip ─────────────────────────────
    // exp_vals (Q8, *256) * recip (Q15, *32768) = Q23; >>15 -> Q8
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            for (int i = 0; i < N; i++) probs[i] <= '0;
        end else begin
            valid_out <= rec_valid;
            for (int i = 0; i < N; i++) begin
                automatic logic [47:0] prod =
                    {32'b0, exp_delay[EXP_DELAY-1][i]} * {32'b0, recip};
                automatic logic [31:0] result = prod[46:15];
                probs[i] <= (result > 255) ? 8'd255 : result[OUT_W-1:0];
            end
        end
    end

endmodule
