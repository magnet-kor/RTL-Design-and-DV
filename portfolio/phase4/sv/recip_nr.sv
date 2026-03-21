// =============================================================================
// recip_nr.sv — Fixed-Point Reciprocal via Newton-Raphson
// =============================================================================
// Computes 1/S in Q15 fixed-point (result * 2^15).
// Input S is the sum of EXP values from tree_sum (INT32, positive).
//
// Newton-Raphson iteration: x_{n+1} = x_n * (2 - S * x_n)  [Q15 arithmetic]
// Initial guess: leading-bit approximation gives <50% initial error.
// Convergence: quadratic — 4 iterations yield error < 2^-16.
//
// To avoid timing failure from 64-bit multiply in a single cycle,
// each iteration is split into 2 pipeline stages:
//   Phase 0: sx = S * x_n           (64-bit multiply, ~2.0 ns)
//   Phase 1: x_{n+1} = x * (2-sx)   (INT32 range, ~1.8 ns)
// Total latency: 1 (init) + 4*2 (iterations) = 9 cycles
// =============================================================================
`timescale 1ns/1ps

module recip_nr #(
    parameter IN_W  = 32,
    parameter OUT_W = 16,
    parameter ITERS = 4
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [IN_W-1:0]       s_in,
    input  logic                  valid_in,
    output logic [OUT_W-1:0]      recip_out,
    output logic                  valid_out
);
    localparam Q       = 15;
    localparam ONE_Q15 = 32'd32768;
    localparam TWO_Q15 = 32'd65536;

    // Pipeline arrays: ITERS stages, each 2 phases
    logic [31:0] x_pipe  [0:ITERS];
    logic        v_pipe  [0:ITERS];
    logic [31:0] s_reg   [0:ITERS];
    logic [63:0] sx_reg  [0:ITERS-1];   // intermediate S*x product
    logic        phase_r [0:ITERS-1];    // 0=multiply phase, 1=update phase

    // Stage 0: initial guess = 2^(15-k), k = floor(log2(S))
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_pipe[0] <= '0;
            v_pipe[0] <= 1'b0;
            s_reg[0]  <= '0;
        end else begin
            v_pipe[0] <= valid_in;
            s_reg[0]  <= s_in;
            if (s_in == 0) begin
                x_pipe[0] <= 32'hFFFF;
            end else begin
                automatic logic [4:0] k = 31 - $clz(s_in);
                x_pipe[0] <= (k >= Q) ? 32'd1 : (ONE_Q15 >> k);
            end
        end
    end

    // NR iterations: 2 pipeline stages per iteration
    generate
        for (genvar i = 0; i < ITERS; i++) begin : gen_nr
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    x_pipe[i+1] <= '0;
                    v_pipe[i+1] <= 1'b0;
                    s_reg[i+1]  <= '0;
                    sx_reg[i]   <= '0;
                    phase_r[i]  <= '0;
                end else begin
                    v_pipe[i+1] <= v_pipe[i];
                    s_reg[i+1]  <= s_reg[i];

                    if (phase_r[i] == 0) begin
                        // Phase 0: 64-bit multiply S * x
                        sx_reg[i]   <= s_reg[i] * x_pipe[i];
                        x_pipe[i+1] <= x_pipe[i];
                        phase_r[i]  <= 1;
                    end else begin
                        // Phase 1: x = x * (2 - S*x >> Q) >> Q
                        automatic logic [63:0] two_sx =
                            TWO_Q15 - sx_reg[i][Q + IN_W - 1 : Q];
                        automatic logic [63:0] xx =
                            x_pipe[i] * two_sx;
                        x_pipe[i+1] <= xx[Q + 31 : Q];
                        phase_r[i]  <= 0;
                    end
                end
            end
        end
    endgenerate

    assign recip_out  = (x_pipe[ITERS] > 32'hFFFF) ?
                        16'hFFFF : x_pipe[ITERS][OUT_W-1:0];
    assign valid_out  = v_pipe[ITERS];

endmodule
