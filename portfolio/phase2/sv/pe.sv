// =============================================================================
// pe.sv — Processing Element (Output Stationary)
// 8x8 NPU Systolic Array
// =============================================================================
// Each PE accumulates one output partial sum.
// Activation streams top→bottom; weight streams left→right.
// Output stationary: acc_reg holds the partial sum until drain.
// =============================================================================
`timescale 1ns/1ps

module pe #(
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic signed [DATA_W-1:0]      top_in,    // activation from above
    input  logic signed [DATA_W-1:0]      left_in,   // weight from left
    input  logic                          pe_en,     // compute enable
    input  logic                          drain,     // output partial sum
    output logic signed [DATA_W-1:0]      top_out,   // pass activation down
    output logic signed [DATA_W-1:0]      left_out,  // pass weight right
    output logic signed [ACC_W-1:0]       mac_out,   // accumulated result
    output logic                          mac_valid
);
    logic signed [ACC_W-1:0]  acc_reg;
    logic signed [DATA_W-1:0] top_reg;
    logic signed [DATA_W-1:0] left_reg;
    logic                      drain_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_reg   <= '0;
            top_reg   <= '0;
            left_reg  <= '0;
            drain_r   <= 1'b0;
            mac_valid <= 1'b0;
        end else begin
            // Pipeline registers
            top_reg  <= top_in;
            left_reg <= left_in;
            drain_r  <= drain;
            mac_valid <= drain_r;

            // MAC accumulation (Output Stationary)
            if (pe_en)
                acc_reg <= acc_reg + $signed(top_in) * $signed(left_in);

            // Drain: reset after output
            if (drain)
                acc_reg <= '0;
        end
    end

    assign top_out  = top_reg;
    assign left_out = left_reg;
    assign mac_out  = acc_reg;

endmodule
