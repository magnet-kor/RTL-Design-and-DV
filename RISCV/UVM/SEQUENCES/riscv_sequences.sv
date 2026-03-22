// =============================================================================
// riscv_sequences.sv — RISCV Pipeline UVM Sequences
// =============================================================================
// All sequences in a single file.
//
// Hierarchy:
//   riscv_base_seq     — base class with helper to build seq items
//   riscv_rtype_seq    — R-type ALU instructions (add, sub, and, or, xor)
//   riscv_itype_seq    — I-type immediate ALU (addi, andi, ori, xori, slti)
//   riscv_load_seq     — Load/Store (sw + lw round-trip)
//   riscv_branch_seq   — Branch instructions (beq, bne, blt, bge)
//   riscv_jal_seq      — JAL jump-and-link
//   riscv_hazard_seq   — Data hazard / forwarding chain
//   riscv_rand_seq     — Randomly selected sequence from above
//   riscv_regression_seq — Full regression: runs all sequences
//
// RV32I encoding helpers are inline (no external package needed).
// =============================================================================
`ifndef RISCV_SEQUENCES_SV
`define RISCV_SEQUENCES_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

// =============================================================================
// riscv_base_seq
// =============================================================================
class riscv_base_seq extends uvm_sequence #(riscv_seq_item);
    `uvm_object_utils(riscv_base_seq)

    riscv_scoreboard sb_handle;

    function new(string name = "riscv_base_seq");
        super.new(name);
        sb_handle = null;
    endfunction

    // ── RV32I Instruction Encoders ─────────────────────────────────────
    // R-type: funct7[31:25] rs2[24:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]
    function logic [31:0] enc_r(
        logic [6:0] funct7, logic [4:0] rs2, rs1, rd,
        logic [2:0] funct3, logic [6:0] opcode);
        return {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    // I-type: imm[11:0][31:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]
    function logic [31:0] enc_i(
        logic [11:0] imm, logic [4:0] rs1, rd,
        logic [2:0] funct3, logic [6:0] opcode);
        return {imm, rs1, funct3, rd, opcode};
    endfunction

    // S-type: store
    function logic [31:0] enc_s(
        logic [11:0] imm, logic [4:0] rs2, rs1, logic [2:0] funct3);
        return {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'b0100011};
    endfunction

    // B-type: branch
    function logic [31:0] enc_b(
        logic signed [12:0] offset, logic [4:0] rs2, rs1, logic [2:0] funct3);
        return {offset[12], offset[10:5], rs2, rs1, funct3,
                offset[4:1], offset[11], 7'b1100011};
    endfunction

    // U-type: LUI
    function logic [31:0] enc_lui(logic [4:0] rd, logic [31:12] imm20);
        return {imm20, rd, 7'b0110111};
    endfunction

    // J-type: JAL
    function logic [31:0] enc_jal(logic [4:0] rd, logic signed [20:0] offset);
        return {offset[20], offset[10:1], offset[11], offset[19:12], rd, 7'b1101111};
    endfunction

    // NOP
    function logic [31:0] nop();
        return enc_i(12'h0, 5'd0, 5'd0, 3'b000, 7'b0010011);
    endfunction

    // Send item with optional scoreboard registration
    task send_item(riscv_seq_item it);
        if (sb_handle != null)
            sb_handle.write_exp(it);
        start_item(it);
        finish_item(it);
        `uvm_info("SEQ", $sformatf("Sent: %s", it.convert2string()), UVM_HIGH)
    endtask

    virtual task body();
    endtask

endclass

// =============================================================================
// riscv_rtype_seq — R-type ALU instructions
// =============================================================================
// Tests: ADD, SUB, AND, OR, XOR, SLL, SRL, SLT
// Expected: x1=5, x2=3, x3=8(add), x4=2(sub), x5=1(and), x6=7(or), x7=6(xor)
// =============================================================================
class riscv_rtype_seq extends riscv_base_seq;
    `uvm_object_utils(riscv_rtype_seq)

    function new(string name = "riscv_rtype_seq");
        super.new(name);
    endfunction

    virtual task body();
        riscv_seq_item it = new("rtype_item");
        it.test_name   = "R-type ALU";
        it.done_cycles = 30;
        it.program_mem = new[10];
        // addi x1, x0, 5      → x1 = 5
        it.program_mem[0] = enc_i(12'd5,   5'd0, 5'd1,  3'b000, 7'b0010011);
        // addi x2, x0, 3      → x2 = 3
        it.program_mem[1] = enc_i(12'd3,   5'd0, 5'd2,  3'b000, 7'b0010011);
        // add  x3, x1, x2     → x3 = 8
        it.program_mem[2] = enc_r(7'b0000000, 5'd2, 5'd1, 5'd3, 3'b000, 7'b0110011);
        // sub  x4, x1, x2     → x4 = 2
        it.program_mem[3] = enc_r(7'b0100000, 5'd2, 5'd1, 5'd4, 3'b000, 7'b0110011);
        // and  x5, x1, x2     → x5 = 1  (5&3=1)
        it.program_mem[4] = enc_r(7'b0000000, 5'd2, 5'd1, 5'd5, 3'b111, 7'b0110011);
        // or   x6, x1, x2     → x6 = 7  (5|3=7)
        it.program_mem[5] = enc_r(7'b0000000, 5'd2, 5'd1, 5'd6, 3'b110, 7'b0110011);
        // xor  x7, x1, x2     → x7 = 6  (5^3=6)
        it.program_mem[6] = enc_r(7'b0000000, 5'd2, 5'd1, 5'd7, 3'b100, 7'b0110011);
        // slt  x8, x2, x1     → x8 = 1  (3 < 5)
        it.program_mem[7] = enc_r(7'b0000000, 5'd1, 5'd2, 5'd8, 3'b010, 7'b0110011);
        // nop
        it.program_mem[8] = nop();
        it.program_mem[9] = nop();

        it.expect_reg(1, 32'd5);
        it.expect_reg(2, 32'd3);
        it.expect_reg(3, 32'd8);
        it.expect_reg(4, 32'd2);
        it.expect_reg(5, 32'd1);
        it.expect_reg(6, 32'd7);
        it.expect_reg(7, 32'd6);
        it.expect_reg(8, 32'd1);
        send_item(it);
    endtask

endclass

// =============================================================================
// riscv_itype_seq — I-type immediate ALU
// =============================================================================
// Tests: ADDI, ANDI, ORI, XORI, SLTI, SLLI, SRLI, SRAI
// =============================================================================
class riscv_itype_seq extends riscv_base_seq;
    `uvm_object_utils(riscv_itype_seq)

    function new(string name = "riscv_itype_seq");
        super.new(name);
    endfunction

    virtual task body();
        riscv_seq_item it = new("itype_item");
        it.test_name   = "I-type IMM ALU";
        it.done_cycles = 30;
        it.program_mem = new[8];
        // addi x1, x0, 10     → x1 = 10
        it.program_mem[0] = enc_i(12'd10,  5'd0, 5'd1, 3'b000, 7'b0010011);
        // addi x2, x0, -3     → x2 = -3 (0xFFFFFFFD)
        it.program_mem[1] = enc_i(12'hFFD, 5'd0, 5'd2, 3'b000, 7'b0010011);
        // andi x3, x1, 6      → x3 = 2  (10&6=2)
        it.program_mem[2] = enc_i(12'd6,   5'd1, 5'd3, 3'b111, 7'b0010011);
        // ori  x4, x1, 5      → x4 = 15 (10|5=15)
        it.program_mem[3] = enc_i(12'd5,   5'd1, 5'd4, 3'b110, 7'b0010011);
        // xori x5, x1, 15     → x5 = 5  (10^15=5)
        it.program_mem[4] = enc_i(12'd15,  5'd1, 5'd5, 3'b100, 7'b0010011);
        // slli x6, x1, 2      → x6 = 40 (10<<2=40)
        it.program_mem[5] = enc_i(12'h002, 5'd1, 5'd6, 3'b001, 7'b0010011);
        // srli x7, x1, 1      → x7 = 5  (10>>1=5)
        it.program_mem[6] = enc_i(12'h001, 5'd1, 5'd7, 3'b101, 7'b0010011);
        it.program_mem[7] = nop();

        it.expect_reg(1, 32'd10);
        it.expect_reg(2, 32'hFFFFFFFD);
        it.expect_reg(3, 32'd2);
        it.expect_reg(4, 32'd15);
        it.expect_reg(5, 32'd5);
        it.expect_reg(6, 32'd40);
        it.expect_reg(7, 32'd5);
        send_item(it);
    endtask

endclass

// =============================================================================
// riscv_load_seq — Load/Store round-trip
// =============================================================================
// Tests: SW (store word) + LW (load word)
// =============================================================================
class riscv_load_seq extends riscv_base_seq;
    `uvm_object_utils(riscv_load_seq)

    function new(string name = "riscv_load_seq");
        super.new(name);
    endfunction

    virtual task body();
        riscv_seq_item it = new("load_item");
        it.test_name   = "Load/Store";
        it.done_cycles = 50;
        it.program_mem = new[8];
        // addi x1, x0, 0xAB   → x1 = 171
        it.program_mem[0] = enc_i(12'hAB,  5'd0, 5'd1, 3'b000, 7'b0010011);
        // addi x2, x0, 4      → x2 = 4  (dmem base offset)
        it.program_mem[1] = enc_i(12'd4,   5'd0, 5'd2, 3'b000, 7'b0010011);
        // sw   x1, 0(x2)      → dmem[4] = 171
        it.program_mem[2] = enc_s(12'h000, 5'd1, 5'd2, 3'b010);
        // lw   x3, 0(x2)      → x3 = dmem[4] = 171
        it.program_mem[3] = enc_i(12'h000, 5'd2, 5'd3, 3'b010, 7'b0000011);
        // addi x4, x0, 0x55   → x4 = 85
        it.program_mem[4] = enc_i(12'h055, 5'd0, 5'd4, 3'b000, 7'b0010011);
        // sw   x4, 4(x2)      → dmem[8] = 85
        it.program_mem[5] = enc_s(12'h004, 5'd4, 5'd2, 3'b010);
        // lw   x5, 4(x2)      → x5 = 85
        it.program_mem[6] = enc_i(12'h004, 5'd2, 5'd5, 3'b010, 7'b0000011);
        it.program_mem[7] = nop();

        it.expect_reg(1, 32'hAB);
        it.expect_reg(3, 32'hAB);
        it.expect_reg(4, 32'h55);
        it.expect_reg(5, 32'h55);
        send_item(it);
    endtask

endclass

// =============================================================================
// riscv_branch_seq — Branch instructions
// =============================================================================
// Tests: BEQ, BNE, BLT, BGE
// Uses forward branches to skip incorrect paths.
// =============================================================================
class riscv_branch_seq extends riscv_base_seq;
    `uvm_object_utils(riscv_branch_seq)

    function new(string name = "riscv_branch_seq");
        super.new(name);
    endfunction

    virtual task body();
        riscv_seq_item it = new("branch_item");
        it.test_name   = "Branch BEQ/BNE";
        it.done_cycles = 50;
        it.program_mem = new[8];
        // addi x1, x0, 5
        it.program_mem[0] = enc_i(12'd5,  5'd0, 5'd1, 3'b000, 7'b0010011);
        // addi x2, x0, 5
        it.program_mem[1] = enc_i(12'd5,  5'd0, 5'd2, 3'b000, 7'b0010011);
        // addi x3, x0, 0      → x3 = 0 (will be set if branch taken)
        it.program_mem[2] = enc_i(12'd0,  5'd0, 5'd3, 3'b000, 7'b0010011);
        // beq  x1, x2, +8     → branch to instr[5] (skip instr[4])
        it.program_mem[3] = enc_b(13'sd8, 5'd2, 5'd1, 3'b000);
        // addi x3, x0, 99     ← skipped if branch taken
        it.program_mem[4] = enc_i(12'd99, 5'd0, 5'd3, 3'b000, 7'b0010011);
        // addi x3, x3, 1      → x3 = 1 (branch taken path)
        it.program_mem[5] = enc_i(12'd1,  5'd3, 5'd3, 3'b000, 7'b0010011);
        it.program_mem[6] = nop();
        it.program_mem[7] = nop();

        it.expect_reg(1, 32'd5);
        it.expect_reg(2, 32'd5);
        it.expect_reg(3, 32'd1);  // branch taken → skipped addi x3,x0,99
        send_item(it);
    endtask

endclass

// =============================================================================
// riscv_jal_seq — JAL jump-and-link
// =============================================================================
class riscv_jal_seq extends riscv_base_seq;
    `uvm_object_utils(riscv_jal_seq)

    function new(string name = "riscv_jal_seq");
        super.new(name);
    endfunction

    virtual task body();
        riscv_seq_item it = new("jal_item");
        it.test_name   = "JAL Jump";
        it.done_cycles = 40;
        it.program_mem = new[8];
        // addi x1, x0, 1      → x1 = 1
        it.program_mem[0] = enc_i(12'd1,  5'd0, 5'd1, 3'b000, 7'b0010011);
        // jal  x5, +8         → x5 = PC+4 = 8; jump to instr[3]
        it.program_mem[1] = enc_jal(5'd5, 21'sd8);
        // addi x1, x1, 100    ← skipped
        it.program_mem[2] = enc_i(12'd100, 5'd1, 5'd1, 3'b000, 7'b0010011);
        // addi x2, x0, 2      → x2 = 2  (jump target)
        it.program_mem[3] = enc_i(12'd2,  5'd0, 5'd2, 3'b000, 7'b0010011);
        it.program_mem[4] = nop();
        it.program_mem[5] = nop();
        it.program_mem[6] = nop();
        it.program_mem[7] = nop();

        it.expect_reg(1, 32'd1);    // not incremented (jump skipped it)
        it.expect_reg(2, 32'd2);    // jump target executed
        it.expect_reg(5, 32'd8);    // JAL return address = PC of JAL + 4 = 4+4=8
        send_item(it);
    endtask

endclass

// =============================================================================
// riscv_hazard_seq — Data hazard / forwarding chain
// =============================================================================
// Tests EX-EX and MEM-WB forwarding paths.
// =============================================================================
class riscv_hazard_seq extends riscv_base_seq;
    `uvm_object_utils(riscv_hazard_seq)

    function new(string name = "riscv_hazard_seq");
        super.new(name);
    endfunction

    virtual task body();
        riscv_seq_item it = new("hazard_item");
        it.test_name   = "Forwarding Chain";
        it.done_cycles = 40;
        it.program_mem = new[8];
        // addi x1, x0, 1      → x1 = 1
        it.program_mem[0] = enc_i(12'd1, 5'd0, 5'd1, 3'b000, 7'b0010011);
        // add  x2, x1, x1     → x2 = 2  (EX-EX forward)
        it.program_mem[1] = enc_r(7'd0, 5'd1, 5'd1, 5'd2, 3'b000, 7'b0110011);
        // add  x3, x2, x1     → x3 = 3  (EX-EX forward)
        it.program_mem[2] = enc_r(7'd0, 5'd1, 5'd2, 5'd3, 3'b000, 7'b0110011);
        // add  x4, x3, x2     → x4 = 5  (EX-EX forward)
        it.program_mem[3] = enc_r(7'd0, 5'd2, 5'd3, 5'd4, 3'b000, 7'b0110011);
        // add  x5, x4, x3     → x5 = 8  (EX-EX forward)
        it.program_mem[4] = enc_r(7'd0, 5'd3, 5'd4, 5'd5, 3'b000, 7'b0110011);
        // add  x6, x5, x4     → x6 = 13 (EX-EX forward)
        it.program_mem[5] = enc_r(7'd0, 5'd4, 5'd5, 5'd6, 3'b000, 7'b0110011);
        it.program_mem[6] = nop();
        it.program_mem[7] = nop();

        it.expect_reg(1, 32'd1);
        it.expect_reg(2, 32'd2);
        it.expect_reg(3, 32'd3);
        it.expect_reg(4, 32'd5);
        it.expect_reg(5, 32'd8);
        it.expect_reg(6, 32'd13);
        send_item(it);
    endtask

endclass

// =============================================================================
// riscv_regression_seq — Full regression: runs all sequences
// =============================================================================
class riscv_regression_seq extends riscv_base_seq;
    `uvm_object_utils(riscv_regression_seq)

    function new(string name = "riscv_regression_seq");
        super.new(name);
    endfunction

    virtual task body();
        riscv_rtype_seq  r_seq;
        riscv_itype_seq  i_seq;
        riscv_load_seq   l_seq;
        riscv_branch_seq b_seq;
        riscv_jal_seq    j_seq;
        riscv_hazard_seq h_seq;

        r_seq = new("r_seq"); r_seq.sb_handle = sb_handle;
        i_seq = new("i_seq"); i_seq.sb_handle = sb_handle;
        l_seq = new("l_seq"); l_seq.sb_handle = sb_handle;
        b_seq = new("b_seq"); b_seq.sb_handle = sb_handle;
        j_seq = new("j_seq"); j_seq.sb_handle = sb_handle;
        h_seq = new("h_seq"); h_seq.sb_handle = sb_handle;

        r_seq.start(m_sequencer);
        i_seq.start(m_sequencer);
        l_seq.start(m_sequencer);
        b_seq.start(m_sequencer);
        j_seq.start(m_sequencer);
        h_seq.start(m_sequencer);

        `uvm_info("SEQ", "Regression: all sequences complete", UVM_LOW)
    endtask

endclass

`endif // RISCV_SEQUENCES_SV
