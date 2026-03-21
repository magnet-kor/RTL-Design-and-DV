// =============================================================================
// tree_max.sv — Pipelined Tree Reduction: MAX
// =============================================================================
// Computes MAX(in[0:N-1]) using a binary tree of comparators.
// Latency = $clog2(N) cycles (pipelined registers at each level).
// N=8  → 3 cycles = 15 ns @ 200 MHz
// N=512→ 9 cycles = 45 ns @ 200 MHz  (vs sequential 511 cycles)
// Area: N-1 comparators + N-1 pipeline registers
// =============================================================================
`timescale 1ns/1ps

module tree_max #(
    parameter N      = 8,
    parameter DATA_W = 8,
    parameter LEVELS = $clog2(N)
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic signed [DATA_W-1:0]      in       [0:N-1],
    input  logic                          valid_in,
    output logic signed [DATA_W-1:0]      max_out,
    output logic                          valid_out
);
    logic signed [DATA_W-1:0] stage [0:LEVELS-1][0:N/2-1];
    logic                      valid [0:LEVELS-1];

    // Level 0: N/2 comparators
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid[0] <= 1'b0;
        end else begin
            valid[0] <= valid_in;
            for (int i = 0; i < N/2; i++)
                stage[0][i] <= ($signed(in[2*i]) > $signed(in[2*i+1]))
                               ? in[2*i] : in[2*i+1];
        end
    end

    // Levels 1 through LEVELS-1
    generate
        for (genvar l = 1; l < LEVELS; l++) begin : gen_levels
            localparam int NODES = N >> (l+1);
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    valid[l] <= 1'b0;
                end else begin
                    valid[l] <= valid[l-1];
                    for (int i = 0; i < NODES; i++)
                        stage[l][i] <= ($signed(stage[l-1][2*i]) >
                                        $signed(stage[l-1][2*i+1]))
                                       ? stage[l-1][2*i] : stage[l-1][2*i+1];
                    for (int i = NODES; i < N/2; i++)
                        stage[l][i] <= '0;
                end
            end
        end
    endgenerate

    assign max_out   = stage[LEVELS-1][0];
    assign valid_out = valid[LEVELS-1];

endmodule
