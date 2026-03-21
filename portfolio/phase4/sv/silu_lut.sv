// =============================================================================
// silu_lut.sv — SiLU Activation Look-Up Table (ROM)
// =============================================================================
// SiLU(x) = x * sigmoid(x) = x / (1 + exp(-x))
// Input: INT8 x in [-128, 127], encoded as addr = x + 128 (UINT8).
// Output: INT8 SiLU(x), clipped to [-128, 127].
// Latency: 1 cycle (registered ROM)
// LUT size: 256 * 1 byte = 256 bytes
//
// Comparison vs EXP-based computation (exp + recip + mul = 8 cycles):
//   LUT: 1 cycle, 256 B  →  8x faster, same INT8 accuracy (±0.4%)
// Initialize with: $readmemh("silu_lut.hex", rom)
// =============================================================================
`timescale 1ns/1ps

module silu_lut #(
    parameter ADDR_W = 8,
    parameter DATA_W = 8
)(
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic [ADDR_W-1:0]        addr,       // = x_int + 128
    input  logic                     valid_in,
    output logic signed [DATA_W-1:0] data,       // SiLU(x_int), INT8
    output logic                     valid_out
);
    logic signed [DATA_W-1:0] rom [0:(1<<ADDR_W)-1];

    initial begin
        $readmemh("silu_lut.hex", rom);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data      <= '0;
            valid_out <= 1'b0;
        end else begin
            data      <= rom[addr];
            valid_out <= valid_in;
        end
    end

endmodule
