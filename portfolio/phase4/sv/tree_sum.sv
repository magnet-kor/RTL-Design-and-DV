// =============================================================================
// tree_sum.sv — Pipelined Tree Reduction: SUM
// =============================================================================
// Computes SUM(in[0:N-1]) using a binary adder tree.
// Latency = $clog2(N) cycles (same structure as tree_max).
// Bit-width grows by 1 per level to prevent overflow.
// Used by softmax (Σ exp values) and RMSNorm (Σ x²).
// =============================================================================
`timescale 1ns/1ps

module tree_sum #(
    parameter N      = 8,
    parameter IN_W   = 16,
    parameter OUT_W  = 32,
    parameter LEVELS = $clog2(N)
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [IN_W-1:0]       in       [0:N-1],
    input  logic                  valid_in,
    output logic [OUT_W-1:0]      sum_out,
    output logic                  valid_out
);
    logic [OUT_W-1:0] stage [0:LEVELS-1][0:N/2-1];
    logic             valid [0:LEVELS-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid[0] <= 1'b0;
        end else begin
            valid[0] <= valid_in;
            for (int i = 0; i < N/2; i++)
                stage[0][i] <= {{(OUT_W-IN_W){1'b0}}, in[2*i]}
                             + {{(OUT_W-IN_W){1'b0}}, in[2*i+1]};
        end
    end

    generate
        for (genvar l = 1; l < LEVELS; l++) begin : gen_levels
            localparam int NODES = N >> (l+1);
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    valid[l] <= 1'b0;
                end else begin
                    valid[l] <= valid[l-1];
                    for (int i = 0; i < NODES; i++)
                        stage[l][i] <= stage[l-1][2*i] + stage[l-1][2*i+1];
                    for (int i = NODES; i < N/2; i++)
                        stage[l][i] <= '0;
                end
            end
        end
    endgenerate

    assign sum_out   = stage[LEVELS-1][0];
    assign valid_out = valid[LEVELS-1];

endmodule
