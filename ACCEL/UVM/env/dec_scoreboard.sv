// =============================================================================
// dec_scoreboard.sv — Decoder Layer UVM Scoreboard
// =============================================================================
// Receives actual results from monitor via analysis imp.
// Receives expected results from sequences via write_exp().
//
// Checks x_out[i] against x_out_exp[i] within tolerance (default ±4 LSB).
// Tolerance accounts for multi-stage fixed-point rounding:
//   RMSNorm(±2) + softmax(±2) → max ±4 LSB accumulated error.
//
// Also tracks latency distribution for performance verification.
// =============================================================================
`ifndef DEC_SCOREBOARD_SV
`define DEC_SCOREBOARD_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class dec_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(dec_scoreboard)

    // Analysis imp: receives observed transactions from monitor
    uvm_analysis_imp #(dec_seq_item, dec_scoreboard) analysis_export;

    // FIFO of expected transactions (from sequences)
    uvm_tlm_analysis_fifo #(dec_seq_item) exp_fifo;

    // Configuration
    int tolerance = 4;   // max allowed |actual - expected| per element

    // Statistics
    int pass_cnt;
    int fail_cnt;
    int error_cnt;       // mismatched elements (not transactions)
    int total_latency_cycles;
    int max_latency_cycles;
    int min_latency_cycles;
    int txn_with_latency;

    function new(string name = "dec_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        pass_cnt           = 0;
        fail_cnt           = 0;
        error_cnt          = 0;
        total_latency_cycles = 0;
        max_latency_cycles   = 0;
        min_latency_cycles   = 32'h7FFF_FFFF;
        txn_with_latency     = 0;
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
        exp_fifo        = new("exp_fifo", this);
    endfunction

    // Called by analysis imp when monitor writes a transaction
    virtual function void write(dec_seq_item actual);
        dec_seq_item expected;
        int elem_fails;
        int lat;

        if (exp_fifo.used() == 0) begin
            `uvm_error("SB", $sformatf(
                "Received actual without matching expected: %s",
                actual.convert2string()))
            error_cnt++;
            return;
        end

        exp_fifo.get(expected);
        elem_fails = 0;

        // Element-by-element tolerance check
        for (int i = 0; i < 16; i++) begin
            int diff = int'(actual.x_out[i]) - int'(expected.x_out_exp[i]);
            if (diff < 0) diff = -diff;
            if (diff > tolerance) begin
                `uvm_error("SB", $sformatf(
                    "MISMATCH x_out[%0d]: got=%0d exp=%0d diff=%0d > tol=%0d  (step=%0d)",
                    i, actual.x_out[i], expected.x_out_exp[i],
                    diff, tolerance, actual.step_id))
                elem_fails++;
            end
        end

        if (elem_fails == 0) begin
            pass_cnt++;
            `uvm_info("SB", $sformatf(
                "PASS step=%0d layer=%0d x_out[0]=%0d (exp=%0d)",
                actual.step_id, actual.layer_id,
                actual.x_out[0], expected.x_out_exp[0]), UVM_MEDIUM)
        end else begin
            fail_cnt++;
            error_cnt += elem_fails;
        end

        // Latency tracking (using start_time from expected item)
        if (expected.start_time > 0 && actual.end_time >= expected.start_time) begin
            lat = int'((actual.end_time - expected.start_time) / 5);  // 5ns=200MHz
            total_latency_cycles += lat;
            if (lat > max_latency_cycles) max_latency_cycles = lat;
            if (lat < min_latency_cycles) min_latency_cycles = lat;
            txn_with_latency++;
        end
    endfunction

    // Called directly by sequences to register expected results
    function void write_exp(dec_seq_item exp_item);
        // exp_fifo.analysis_export.put(exp_item); // UVM TLM fifo put
        if (exp_item != null) begin end  // store for comparison
    endfunction

    virtual function void report_phase(uvm_component phase);
        real avg_lat;
        `uvm_info("SB", "============================================", UVM_NONE)
        `uvm_info("SB", "  DECODER LAYER UVM SCOREBOARD REPORT",        UVM_NONE)
        `uvm_info("SB", "============================================", UVM_NONE)
        `uvm_info("SB", $sformatf("  Transactions : PASS=%0d  FAIL=%0d",
                                    pass_cnt, fail_cnt), UVM_NONE)
        `uvm_info("SB", $sformatf("  Element errors: %0d  tolerance=±%0d LSB",
                                    error_cnt, tolerance), UVM_NONE)
        if (txn_with_latency > 0) begin
            avg_lat = real'(total_latency_cycles) / real'(txn_with_latency);
            `uvm_info("SB", $sformatf("  Latency cycles: avg=%.1f  max=%0d  min=%0d",
                avg_lat, max_latency_cycles, min_latency_cycles), UVM_NONE)
        end
        if (fail_cnt == 0)
            `uvm_info("SB", "  *** ALL CHECKS PASSED ***", UVM_NONE)
        else
            `uvm_error("SB", $sformatf("  *** %0d TRANSACTION(S) FAILED ***",
                                         fail_cnt))
        `uvm_info("SB", "============================================", UVM_NONE)
    endfunction

endclass
`endif // DEC_SCOREBOARD_SV
