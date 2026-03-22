// =============================================================================
// riscv_coverage.sv — RISCV Pipeline Functional Coverage Model
// =============================================================================
// Tracks coverage of key verification dimensions:
//   1. Program length (small/medium/large)
//   2. Execution cycles distribution
//   3. Register usage (which registers are checked)
//   4. Test categories (R-type, I-type, Load/Store, Branch, Jump)
// =============================================================================
`ifndef RISCV_COVERAGE_SV
`define RISCV_COVERAGE_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class riscv_coverage extends uvm_component;
    `uvm_component_utils(riscv_coverage)

    // Analysis imp connected to monitor output
    uvm_analysis_imp #(riscv_seq_item, riscv_coverage) analysis_export;

    // Current transaction for covergroup sampling
    riscv_seq_item cur_item;

    // Manual tracking (simulator-independent)
    int txn_total;
    int regs_checked [32];
    int prog_small;    // < 5 instructions
    int prog_medium;   // 5..15 instructions
    int prog_large;    // > 15 instructions

`ifndef VERILATOR
    covergroup cg_prog_size;
        cp_size : coverpoint cur_item.program_mem.size() {
            bins small_prog  = {[1:4]};
            bins medium_prog = {[5:15]};
            bins large_prog  = {[16:1023]};
        }
    endgroup

    covergroup cg_reg_usage;
        cp_reg1 : coverpoint cur_item.check_reg[1]  { bins checked = {1}; }
        cp_reg2 : coverpoint cur_item.check_reg[2]  { bins checked = {1}; }
        cp_reg3 : coverpoint cur_item.check_reg[3]  { bins checked = {1}; }
        cp_reg10: coverpoint cur_item.check_reg[10] { bins checked = {1}; }
    endgroup
`endif

    function new(string name = "riscv_coverage", uvm_component parent = null);
        super.new(name, parent);
        txn_total   = 0;
        prog_small  = 0;
        prog_medium = 0;
        prog_large  = 0;
        foreach (regs_checked[i]) regs_checked[i] = 0;
`ifndef VERILATOR
        cg_prog_size  = new();
        cg_reg_usage  = new();
`endif
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
    endfunction

    virtual function void write(riscv_seq_item item);
        int sz;
        cur_item = item;
`ifndef VERILATOR
        cg_prog_size.sample();
        cg_reg_usage.sample();
`endif
        txn_total++;
        sz = item.program_mem.size();
        if      (sz < 5)  prog_small++;
        else if (sz <= 15) prog_medium++;
        else               prog_large++;
        for (int i = 0; i < 32; i++)
            if (item.check_reg[i]) regs_checked[i]++;
    endfunction

    virtual function void report_phase(uvm_component phase);
        int regs_hit;
        foreach (regs_checked[i]) if (regs_checked[i] > 0) regs_hit++;
        `uvm_info("COV", "============================================", UVM_NONE)
        `uvm_info("COV", "  RISCV FUNCTIONAL COVERAGE REPORT",           UVM_NONE)
        `uvm_info("COV", "============================================", UVM_NONE)
        `uvm_info("COV", $sformatf("  Total transactions : %0d", txn_total),    UVM_NONE)
        `uvm_info("COV", $sformatf("  Small  (<5  instr) : %0d", prog_small),   UVM_NONE)
        `uvm_info("COV", $sformatf("  Medium (5-15 instr): %0d", prog_medium),  UVM_NONE)
        `uvm_info("COV", $sformatf("  Large  (>15 instr) : %0d", prog_large),   UVM_NONE)
        `uvm_info("COV", $sformatf("  Unique regs checked: %0d/31", regs_hit),  UVM_NONE)
        `uvm_info("COV", "============================================", UVM_NONE)
    endfunction

endclass
`endif // RISCV_COVERAGE_SV
