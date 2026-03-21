// =============================================================================
// control.sv — Main Control Unit (RV32I)
// =============================================================================
// Decodes the 7-bit opcode and generates all pipeline control signals.
//
//  Signal      Meaning
//  ──────────  ─────────────────────────────────────────
//  reg_write   Write result to register file
//  alu_src     0=rs2, 1=immediate (ALU B input)
//  mem_write   Write to data memory
//  mem_read    Read from data memory
//  mem_to_reg  0=ALU result → rd, 1=mem data → rd
//  branch      Instruction is a conditional branch
//  jal         Unconditional JAL
//  jalr        Unconditional JALR
//  lui         LUI (pass imm through ALU)
//  auipc       AUIPC (PC + imm)
//  alu_op2     2-bit hint to ALU control unit
// =============================================================================

`timescale 1ns/1ps

module control (
    input  logic [6:0] opcode,
    output logic       reg_write,
    output logic       alu_src,
    output logic       mem_write,
    output logic       mem_read,
    output logic       mem_to_reg,
    output logic       branch,
    output logic       jal,
    output logic       jalr,
    output logic       lui,
    output logic       auipc,
    output logic [1:0] alu_op2
);
    always_comb begin
        // Defaults: NOP-safe
        reg_write  = 1'b0;
        alu_src    = 1'b0;
        mem_write  = 1'b0;
        mem_read   = 1'b0;
        mem_to_reg = 1'b0;
        branch     = 1'b0;
        jal        = 1'b0;
        jalr       = 1'b0;
        lui        = 1'b0;
        auipc      = 1'b0;
        alu_op2    = 2'b00;

        case (opcode)
            7'b0110011: begin // R-type
                reg_write = 1'b1;
                alu_op2   = 2'b10;
            end
            7'b0010011: begin // I-type (OP-IMM)
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op2   = 2'b10;
            end
            7'b0000011: begin // LOAD
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
            end
            7'b0100011: begin // STORE
                alu_src   = 1'b1;
                mem_write = 1'b1;
            end
            7'b1100011: begin // BRANCH
                branch  = 1'b1;
                alu_op2 = 2'b01;
            end
            7'b1101111: begin // JAL
                reg_write = 1'b1;
                jal       = 1'b1;
            end
            7'b1100111: begin // JALR
                reg_write = 1'b1;
                alu_src   = 1'b1;
                jalr      = 1'b1;
            end
            7'b0110111: begin // LUI
                reg_write = 1'b1;
                alu_src   = 1'b1;
                lui       = 1'b1;
            end
            7'b0010111: begin // AUIPC
                reg_write = 1'b1;
                auipc     = 1'b1;
            end
            default: ; // NOP / unimplemented
        endcase
    end

endmodule
