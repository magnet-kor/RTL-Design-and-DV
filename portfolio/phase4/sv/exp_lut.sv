// =============================================================================
// exp_lut.sv — Fixed-Point EXP Look-Up Table (ROM)
// =============================================================================
// Computes exp(x) for x in [-255, 0] using a precomputed 256-entry ROM.
// Input addr encodes x as: addr = x + 255, so addr=255 -> x=0, addr=0 -> x=-255.
// Output is Q8 fixed-point: data = round(exp(x) * 256).
//   exp(0)   * 256 = 256   (lut[255])
//   exp(-1)  * 256 ≈  94   (lut[254])
//   exp(-255)* 256 ≈   0   (lut[0])
// Latency: 1 cycle (registered output)
// LUT size: 256 * 2 bytes = 512 bytes
// Initialize with: $readmemh("exp_lut.hex", rom)
// =============================================================================
`timescale 1ns/1ps

module exp_lut #(
    parameter ADDR_W = 8,
    parameter DATA_W = 16
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [ADDR_W-1:0]     addr,
    input  logic                  valid_in,
    output logic [DATA_W-1:0]     data,
    output logic                  valid_out
);
    logic [DATA_W-1:0] rom [0:(1<<ADDR_W)-1];

    initial begin
        $readmemh("exp_lut.hex", rom);
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
