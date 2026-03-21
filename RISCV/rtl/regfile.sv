// =============================================================================
// regfile.sv — 32×32 Register File (RV32I)
// =============================================================================
// - x0 hardwired to zero
// - Synchronous write, combinatorial read
// - Write-first: if WB writes and ID reads the same register in the same cycle,
//   the read returns the new value (avoids same-cycle RAW hazard)
// - Clears all registers on rst_n de-assertion
// =============================================================================
`timescale 1ns/1ps

module regfile (
    input  logic        clk,
    input  logic        rst_n,
    // Write port (WB stage)
    input  logic        we,
    input  logic [4:0]  wa,
    input  logic [31:0] wd,
    // Read port 1
    input  logic [4:0]  ra1,
    output logic [31:0] rd1,
    // Read port 2
    input  logic [4:0]  ra2,
    output logic [31:0] rd2
);
    logic [31:0] regs [31:0];

    // Synchronous write with synchronous reset
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++) regs[i] <= 32'b0;
        end else if (we && wa != 5'b0) begin
            regs[wa] <= wd;
        end
    end

    // Read with write-first forwarding: same-cycle WB→ID bypass
    assign rd1 = (ra1 == 5'b0)                   ? 32'b0 :
                 (we && wa == ra1 && wa != 5'b0)  ? wd    :
                                                    regs[ra1];

    assign rd2 = (ra2 == 5'b0)                   ? 32'b0 :
                 (we && wa == ra2 && wa != 5'b0)  ? wd    :
                                                    regs[ra2];

endmodule
