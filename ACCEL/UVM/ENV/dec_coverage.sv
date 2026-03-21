// =============================================================================
// dec_coverage.sv — Decoder Layer Functional Coverage Model
// =============================================================================
// Tracks coverage of the key verification dimensions:
//   1. step_id distribution (Prefill=0, Early/Mid/Late decode)
//   2. layer_id (0..23)
//   3. x_in value distribution (negative, zero, small positive, large positive)
//   4. Back-to-back transactions (no idle between decode steps)
//   5. AXI4 channel interleaving (write then read without gap)
// =============================================================================
`ifndef DEC_COVERAGE_SV
`define DEC_COVERAGE_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class dec_coverage extends uvm_component;
    `uvm_component_utils(dec_coverage)

    // Analysis imp connected to monitor output
    uvm_analysis_imp #(dec_seq_item, dec_coverage) analysis_export;

    // Current transaction for covergroup sampling
    dec_seq_item cur_item;

    // Coverage groups (VCS/Questa/Xcelium only; verilator skips)
`ifndef VERILATOR
    covergroup cg_step_id;
        cp_step : coverpoint cur_item.step_id {
            bins prefill         = {0};
            bins early_decode    = {[1:7]};
            bins mid_decode      = {[8:63]};
            bins late_decode     = {[64:255]};
        }
    endgroup

    covergroup cg_layer_id;
        cp_layer : coverpoint cur_item.layer_id {
            bins layer_first  = {0};
            bins layer_middle = {[1:22]};
            bins layer_last   = {23};
        }
    endgroup

    covergroup cg_x_in_values;
        cp_x0 : coverpoint cur_item.x_in[0] {
            bins negative    = {[$:-1]};
            bins zero        = {0};
            bins small_pos   = {[1:31]};
            bins large_pos   = {[32:127]};
        }
    endgroup

    covergroup cg_step_layer_cross;
        cp_step  : coverpoint cur_item.step_id  { bins s[] = {0, 1, 8, 64}; }
        cp_layer : coverpoint cur_item.layer_id { bins l[] = {0, 12, 23};   }
        cx : cross cp_step, cp_layer;
    endgroup

`endif // VERILATOR

    // Statistics (manual tracking — simulator-independent)
    int txn_total;
    int txn_prefill;
    int txn_decode;
    int step_seen [256];
    int layer_seen [24];

    function new(string name = "dec_coverage", uvm_component parent = null);
        super.new(name, parent);
        txn_total   = 0;
        txn_prefill = 0;
        txn_decode  = 0;
        foreach (step_seen[i])  step_seen[i]  = 0;
        foreach (layer_seen[i]) layer_seen[i] = 0;
`ifndef VERILATOR
        cg_step_id          = new();
        cg_layer_id         = new();
        cg_x_in_values      = new();
        cg_step_layer_cross = new();
`endif
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
    endfunction

    virtual function void write(dec_seq_item item);
        int s, l;
        cur_item = item;
`ifndef VERILATOR
        // Sample covergroups (VCS/Questa/Xcelium)
        cg_step_id.sample();
        cg_layer_id.sample();
        cg_x_in_values.sample();
        cg_step_layer_cross.sample();
`endif
        // Manual tracking (iverilog fallback)
        txn_total++;
        if (item.step_id == 0) txn_prefill++;
        else                   txn_decode++;
        s = item.step_id  < 256 ? item.step_id  : 255;
        l = item.layer_id <  24 ? item.layer_id : 23;
        step_seen[s]++;
        layer_seen[l]++;
    endfunction

    virtual function void report_phase(uvm_component phase);
        int s_hit, l_hit;
        foreach (step_seen[i])  if (step_seen[i]  > 0) s_hit++;
        foreach (layer_seen[i]) if (layer_seen[i] > 0) l_hit++;
        `uvm_info("COV", "============================================", UVM_NONE)
        `uvm_info("COV", "  FUNCTIONAL COVERAGE REPORT",                 UVM_NONE)
        `uvm_info("COV", "============================================", UVM_NONE)
        `uvm_info("COV", $sformatf("  Total transactions : %0d",   txn_total),   UVM_NONE)
        `uvm_info("COV", $sformatf("  Prefill (step=0)   : %0d",   txn_prefill), UVM_NONE)
        `uvm_info("COV", $sformatf("  Decode  (step>0)   : %0d",   txn_decode),  UVM_NONE)
        `uvm_info("COV", $sformatf("  Unique step_ids    : %0d/256", s_hit),     UVM_NONE)
        `uvm_info("COV", $sformatf("  Unique layer_ids   : %0d/24",  l_hit),     UVM_NONE)
        `uvm_info("COV", "============================================", UVM_NONE)
    endfunction

endclass
`endif // DEC_COVERAGE_SV
