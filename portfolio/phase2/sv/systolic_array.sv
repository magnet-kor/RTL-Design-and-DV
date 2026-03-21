// =============================================================================
// systolic_array.sv — 8x8 Output Stationary Systolic Array
// =============================================================================
// Performs GEMM: C += A × B using SIZE×SIZE PE array.
//
// Dataflow (Output Stationary):
//   - Activation rows stream from top, skewed by row index
//   - Weight columns stream from left, skewed by column index
//   - Partial sums drain after SIZE cycles
//
// Drain Latency = 2*(SIZE-1) = 14 cycles
// Fill Latency  = SIZE-1 = 7 cycles (pipeline fill)
// Throughput    = 64 MAC/cycle (SIZE^2) once filled
// =============================================================================
`timescale 1ns/1ps

module systolic_array #(
    parameter SIZE   = 8,
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic signed [DATA_W-1:0]      top_data  [0:SIZE-1],  // activation row
    input  logic signed [DATA_W-1:0]      left_data [0:SIZE-1],  // weight column
    input  logic                          data_valid,
    output logic signed [ACC_W-1:0]       bottom_data[0:SIZE-1], // partial sums
    output logic                          out_valid
);
    // ── Skew shift registers ───────────────────────────────────────────────
    // Activation: row r delayed r cycles (top skew)
    // Weight:     col c delayed c cycles (left skew)
    logic signed [DATA_W-1:0] act_skew [0:SIZE-1][0:SIZE-1];
    logic signed [DATA_W-1:0] wgt_skew [0:SIZE-1][0:SIZE-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < SIZE; i++)
                for (int j = 0; j < SIZE; j++) begin
                    act_skew[i][j] <= '0;
                    wgt_skew[i][j] <= '0;
                end
        end else if (data_valid) begin
            for (int i = 0; i < SIZE; i++) begin
                act_skew[i][0] <= top_data[i];
                for (int d = 1; d < SIZE; d++)
                    act_skew[i][d] <= act_skew[i][d-1];
            end
            for (int j = 0; j < SIZE; j++) begin
                wgt_skew[j][0] <= left_data[j];
                for (int d = 1; d < SIZE; d++)
                    wgt_skew[j][d] <= wgt_skew[j][d-1];
            end
        end
    end

    // ── PE array ───────────────────────────────────────────────────────────
    logic signed [DATA_W-1:0] pe_top  [0:SIZE-1][0:SIZE];
    logic signed [DATA_W-1:0] pe_left [0:SIZE][0:SIZE-1];
    logic signed [ACC_W-1:0]  pe_mac  [0:SIZE-1][0:SIZE-1];
    logic                      pe_valid[0:SIZE-1][0:SIZE-1];
    logic                      pe_en;
    logic                      drain_pipe [0:2*(SIZE-1)-1];

    assign pe_en = data_valid;

    // Drain pulse: asserted 2*(SIZE-1) cycles after first data_valid
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 2*(SIZE-1); i++) drain_pipe[i] <= 1'b0;
        end else begin
            drain_pipe[0] <= data_valid;
            for (int i = 1; i < 2*(SIZE-1); i++)
                drain_pipe[i] <= drain_pipe[i-1];
        end
    end

    // Connect skewed inputs to PE array boundaries
    always_comb begin
        for (int i = 0; i < SIZE; i++) begin
            pe_top[i][0]  = act_skew[i][i];    // row i: delayed i cycles
            pe_left[0][i] = wgt_skew[i][i];    // col i: delayed i cycles
        end
    end

    // Instantiate PEs
    generate
        for (genvar r = 0; r < SIZE; r++) begin : gen_row
            for (genvar c = 0; c < SIZE; c++) begin : gen_col
                pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_pe (
                    .clk      (clk),
                    .rst_n    (rst_n),
                    .top_in   (pe_top[r][c]),
                    .left_in  (pe_left[r][c]),
                    .pe_en    (pe_en),
                    .drain    (drain_pipe[2*(SIZE-1)-1]),
                    .top_out  (pe_top[r][c+1]),
                    .left_out (pe_left[r+1][c]),
                    .mac_out  (pe_mac[r][c]),
                    .mac_valid(pe_valid[r][c])
                );
            end
        end
    endgenerate

    // Output: bottom row of PE array
    assign out_valid = pe_valid[SIZE-1][0];
    always_comb begin
        for (int c = 0; c < SIZE; c++)
            bottom_data[c] = pe_mac[SIZE-1][c];
    end

endmodule
