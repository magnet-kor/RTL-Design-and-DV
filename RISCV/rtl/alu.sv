// =============================================================================
// alu.sv — 32-bit ALU for RISC-V RV32I
// =============================================================================
// Operations (alu_op encoding):
//   ADD  0000    SUB  0001
//   AND  0010    OR   0011    XOR  0100
//   SLL  0101    SRL  0110    SRA  0111
//   SLT  1000    SLTU 1001
//   LUI  1010    (pass b directly)
// Zero flag: asserted when result == 0  (used by branch unit)
// =============================================================================

`timescale 1ns/1ps

module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [3:0]  alu_op,
    output logic [31:0] result,
    output logic        zero
);
    logic [4:0]  shamt;
    assign shamt = b[4:0];

    always_comb begin
        case (alu_op)
            4'b0000: result = a + b;                          // ADD
            4'b0001: result = a - b;                          // SUB
            4'b0010: result = a & b;                          // AND
            4'b0011: result = a | b;                          // OR
            4'b0100: result = a ^ b;                          // XOR
            4'b0101: result = a << shamt;                     // SLL
            4'b0110: result = a >> shamt;                     // SRL
            4'b0111: result = $signed(a) >>> shamt;           // SRA
            4'b1000: result = {31'b0, $signed(a) < $signed(b)};  // SLT
            4'b1001: result = {31'b0, a < b};                 // SLTU
            4'b1010: result = b;                              // LUI (pass imm)
            default: result = 32'b0;
        endcase
    end

    assign zero = (result == 32'b0);

endmodule
