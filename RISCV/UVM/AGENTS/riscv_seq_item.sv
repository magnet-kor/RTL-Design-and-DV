// =============================================================================
// riscv_seq_item.sv — RISCV Pipeline UVM Sequence Item
// =============================================================================
// Represents one test transaction:
//   Stimulus : program[] — array of 32-bit RV32I instructions to load into imem
//   Response : regs[]    — register file values captured after execution
//   Expected : exp_regs[] — expected register values (from sequence golden model)
//
// The driver loads program[] into imem starting at address 0.
// The monitor captures regfile after done_cycles idle cycles.
// =============================================================================
`ifndef RISCV_SEQ_ITEM_SV
`define RISCV_SEQ_ITEM_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class riscv_seq_item extends uvm_sequence_item;
    `uvm_object_utils_begin(riscv_seq_item)
        `uvm_field_string(test_name, UVM_ALL_ON)
        `uvm_field_int(done_cycles, UVM_ALL_ON)
    `uvm_object_utils_end

    // ── Stimulus ──────────────────────────────────────────────────────────
    string        test_name;           // human-readable test name
    logic [31:0]  program_mem[];       // instructions to load into imem
    int unsigned  done_cycles;         // cycles to wait after reset before capturing

    // ── Response (monitor-populated) ─────────────────────────────────────
    logic [31:0]  regs[32];            // actual register file values
    time          start_time;
    time          end_time;

    // ── Expected (sequence-populated) ────────────────────────────────────
    logic [31:0]  exp_regs[32];        // expected register values (0 = don't check)
    bit           check_reg[32];       // which registers to check

    function new(string name = "riscv_seq_item");
        super.new(name);
        test_name   = "unnamed";
        done_cycles = 100;
        start_time  = 0;
        end_time    = 0;
        foreach (regs[i])     regs[i]     = 0;
        foreach (exp_regs[i]) exp_regs[i] = 0;
        foreach (check_reg[i]) check_reg[i] = 0;
    endfunction

    // Set expected register value and mark for checking
    function void expect_reg(int reg_num, logic [31:0] value);
        if (reg_num > 0 && reg_num < 32) begin
            exp_regs[reg_num]  = value;
            check_reg[reg_num] = 1;
        end
    endfunction

    virtual function string convert2string();
        return $sformatf("test=%s prog_len=%0d done_cycles=%0d",
            test_name, program_mem.size(), done_cycles);
    endfunction

    // Latency in clock cycles
    function int unsigned latency_cycles(int period_ns = 10);
        if (end_time >= start_time)
            return int'((end_time - start_time) / period_ns);
        return 0;
    endfunction

endclass
`endif // RISCV_SEQ_ITEM_SV
