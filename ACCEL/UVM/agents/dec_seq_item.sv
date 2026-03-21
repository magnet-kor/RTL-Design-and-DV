// =============================================================================
// dec_seq_item.sv — Decoder Layer UVM Sequence Item
// =============================================================================
// One complete decoder layer transaction.
//   Stimulus : step_id, layer_id, x_in[HIDDEN=16]
//   Response : x_out[HIDDEN] — written by monitor after done
//   Expected : x_out_exp[HIDDEN] — written by sequence golden model
//
// step_id=0  → Prefill (hist_len = 1)
// step_id>0  → Decode  (hist_len = step_id + 1)
//
// Porting note: change HIDDEN=16 to 896 for full-size simulation.
// =============================================================================
`ifndef DEC_SEQ_ITEM_SV
`define DEC_SEQ_ITEM_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class dec_seq_item extends uvm_sequence_item;
    `uvm_object_utils_begin(dec_seq_item)
        `uvm_field_int(step_id,  UVM_ALL_ON)
        `uvm_field_int(layer_id, UVM_ALL_ON)
    `uvm_object_utils_end

    // ── Stimulus ──────────────────────────────────────────────────────
    rand int unsigned     step_id;
    rand int unsigned     layer_id;
    rand bit signed [7:0] x_in [0:15];

    // ── Response (monitor-populated) ──────────────────────────────────
    bit signed [7:0] x_out    [0:15];
    bit              done_seen;
    time             start_time;
    time             end_time;

    // ── Expected (sequence golden model) ──────────────────────────────
    bit signed [7:0] x_out_exp [0:15];

    // ── Randomization constraints ─────────────────────────────────────
    constraint c_step  { step_id  inside {[0:255]}; }
    constraint c_layer { layer_id inside {[0:23]};  }
    // Bias toward small values: keep RMSNorm sum within INT32 range
    constraint c_x_in  {
        foreach (x_in[i])
            x_in[i] dist { [-32:31]    := 60,
                            [-128:-33] := 20,
                            [32:127]   := 20 };
    }

    function new(string name = "dec_seq_item");
        super.new(name);
        done_seen  = 0;
        start_time = 0;
        end_time   = 0;
        foreach (x_in[i])      x_in[i]      = 0;
        foreach (x_out[i])     x_out[i]      = 0;
        foreach (x_out_exp[i]) x_out_exp[i]  = 0;
    endfunction

    virtual function string convert2string();
        return $sformatf(
            "step=%0d layer=%0d x_in[0..3]={%0d,%0d,%0d,%0d} done=%b",
            step_id, layer_id, x_in[0], x_in[1], x_in[2], x_in[3],
            done_seen);
    endfunction

    virtual function void do_copy(uvm_object rhs);
        dec_seq_item src;
        if (!$cast(src, rhs)) `uvm_fatal("COPY", "do_copy: type mismatch")
        step_id   = src.step_id;
        layer_id  = src.layer_id;
        done_seen = src.done_seen;
        foreach (x_in[i])      x_in[i]      = src.x_in[i];
        foreach (x_out[i])     x_out[i]      = src.x_out[i];
        foreach (x_out_exp[i]) x_out_exp[i]  = src.x_out_exp[i];
    endfunction

    // Compute latency in clock cycles from timestamps
    function int unsigned latency_cycles(int period_ns = 5);
        if (end_time >= start_time)
            return int'((end_time - start_time) / period_ns);
        return 0;
    endfunction

endclass
`endif // DEC_SEQ_ITEM_SV
