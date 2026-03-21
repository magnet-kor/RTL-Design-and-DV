// =============================================================================
// alu_ctrl.sv — ALU Control Unit
// =============================================================================
// Generates 4-bit alu_op from the 2-bit ALUOp signal (from main control)
// and the funct3/funct7 fields of the instruction.
//
//  alu_op2[1:0]:
//    00 → ADD  (load/store address calculation)
//    01 → SUB  (branch comparison)
//    10 → R-type / I-type (use funct3/funct7)
// =============================================================================

`timescale 1ns/1ps

module alu_ctrl (
    input  logic [1:0] alu_op2,
    input  logic [2:0] funct3,
    input  logic       funct7_5,  // instr[30], distinguishes ADD/SUB, SRL/SRA
    input  logic       op_imm,    // high when opcode is OP-IMM (no funct7)
    output logic [3:0] alu_op
);
    always_comb begin
        case (alu_op2)
            2'b00: alu_op = 4'b0000; // ADD (memory address)
            2'b01: alu_op = 4'b0001; // SUB (branch)
            2'b10: begin
                case (funct3)
                    3'b000: alu_op = (funct7_5 && !op_imm)
                                     ? 4'b0001   // SUB
                                     : 4'b0000;  // ADD / ADDI
                    3'b001: alu_op = 4'b0101;    // SLL
                    3'b010: alu_op = 4'b1000;    // SLT
                    3'b011: alu_op = 4'b1001;    // SLTU
                    3'b100: alu_op = 4'b0100;    // XOR
                    3'b101: alu_op = funct7_5
                                     ? 4'b0111   // SRA
                                     : 4'b0110;  // SRL
                    3'b110: alu_op = 4'b0011;    // OR
                    3'b111: alu_op = 4'b0010;    // AND
                    default: alu_op = 4'b0000;
                endcase
            end
            default: alu_op = 4'b0000;
        endcase
    end

endmodule
