// =============================================================================
// riscv_scoreboard.sv — RISCV Pipeline UVM Scoreboard
// =============================================================================
// Receives actual register snapshots from monitor via analysis imp.
// Receives expected register values from sequences via write_exp().
//
// Checks each marked register (check_reg[i]=1) for exact match.
// x0 is always 0 (hardwired) and is never checked via exp_regs.
//
// Also tracks execution latency for performance analysis.
// =============================================================================
`ifndef RISCV_SCOREBOARD_SV
`define RISCV_SCOREBOARD_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class riscv_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(riscv_scoreboard)

    // Analysis imp: receives observed transactions from monitor
    uvm_analysis_imp #(riscv_seq_item, riscv_scoreboard) analysis_export;

    // FIFO of expected transactions (from sequences)
    uvm_tlm_analysis_fifo #(riscv_seq_item) exp_fifo;

    // Statistics
    int pass_cnt;
    int fail_cnt;
    int error_cnt;
    int total_latency_cycles;
    int max_latency_cycles;
    int txn_count;

    function new(string name = "riscv_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        pass_cnt             = 0;
        fail_cnt             = 0;
        error_cnt            = 0;
        total_latency_cycles = 0;
        max_latency_cycles   = 0;
        txn_count            = 0;
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
        exp_fifo        = new("exp_fifo", this);
    endfunction

    // Called by analysis imp when monitor writes a transaction
    virtual function void write(riscv_seq_item actual);
        riscv_seq_item expected;
        int reg_fails;
        int lat;

        txn_count++;

        if (exp_fifo.used() == 0) begin
            `uvm_error("SB", $sformatf(
                "Received actual txn #%0d without matching expected", txn_count))
            error_cnt++;
            return;
        end

        exp_fifo.get(expected);
        reg_fails = 0;

        // Always check x0 == 0
        if (actual.regs[0] !== 32'h0) begin
            `uvm_error("SB", $sformatf(
                "x0 != 0: got=0x%08h  (test=%s)", actual.regs[0], expected.test_name))
            reg_fails++;
        end

        // Check each marked register
        for (int i = 1; i < 32; i++) begin
            if (expected.check_reg[i]) begin
                if (actual.regs[i] !== expected.exp_regs[i]) begin
                    `uvm_error("SB", $sformatf(
                        "REG MISMATCH x%0d: got=0x%08h exp=0x%08h  (test=%s)",
                        i, actual.regs[i], expected.exp_regs[i],
                        expected.test_name))
                    reg_fails++;
                end
            end
        end

        if (reg_fails == 0) begin
            pass_cnt++;
            `uvm_info("SB", $sformatf(
                "PASS [%s] x1=0x%08h x2=0x%08h x3=0x%08h",
                expected.test_name,
                actual.regs[1], actual.regs[2], actual.regs[3]), UVM_MEDIUM)
        end else begin
            fail_cnt++;
            error_cnt += reg_fails;
        end

        // Latency tracking
        if (expected.start_time > 0 && actual.end_time >= expected.start_time) begin
            lat = int'((actual.end_time - expected.start_time) / 10);
            total_latency_cycles += lat;
            if (lat > max_latency_cycles) max_latency_cycles = lat;
        end
    endfunction

    // Called by sequences to register expected results
    function void write_exp(riscv_seq_item exp_item);
        exp_fifo.analysis_export.write(exp_item);
    endfunction

    virtual function void report_phase(uvm_component phase);
        real avg_lat;
        `uvm_info("SB", "============================================", UVM_NONE)
        `uvm_info("SB", "  RISCV PIPELINE UVM SCOREBOARD REPORT",       UVM_NONE)
        `uvm_info("SB", "============================================", UVM_NONE)
        `uvm_info("SB", $sformatf("  Transactions : PASS=%0d  FAIL=%0d",
                                    pass_cnt, fail_cnt), UVM_NONE)
        `uvm_info("SB", $sformatf("  Register errors : %0d", error_cnt), UVM_NONE)
        if (txn_count > 0) begin
            avg_lat = real'(total_latency_cycles) / real'(txn_count);
            `uvm_info("SB", $sformatf("  Avg latency : %.1f cycles  max=%0d",
                avg_lat, max_latency_cycles), UVM_NONE)
        end
        if (fail_cnt == 0)
            `uvm_info("SB", "  *** ALL CHECKS PASSED ***", UVM_NONE)
        else
            `uvm_error("SB", $sformatf("  *** %0d TRANSACTION(S) FAILED ***",
                                         fail_cnt))
        `uvm_info("SB", "============================================", UVM_NONE)
    endfunction

endclass
`endif // RISCV_SCOREBOARD_SV
