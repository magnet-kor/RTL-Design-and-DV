// =============================================================================
// dec_sequences.sv — Decoder Layer UVM Sequences
// =============================================================================
// All sequences in a single file for easy inclusion.
//
// Hierarchy:
//   dec_base_seq    — base class, golden model helper, write_exp()
//   dec_prefill_seq — single step_id=0 Prefill transaction
//   dec_decode_seq  — N sequential decode steps (step_id=1..N)
//   dec_rand_seq    — fully randomized transactions (N items)
//   dec_stress_seq  — rapid back-to-back transactions, no idle gaps
//
// Golden model (stub x+1):
//   All sequences compute x_out_exp using a stub DUT model
//   (x_out = x_in + 1, clipped to INT8).
//   Replace compute_expected() with the Python-derived exact model
//   when running full regression with the actual decoder_layer DUT.
// =============================================================================
`ifndef DEC_SEQUENCES_SV
`define DEC_SEQUENCES_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

// =============================================================================
// dec_base_seq — base sequence with golden model helper
// =============================================================================
class dec_base_seq extends uvm_sequence #(dec_seq_item);
    `uvm_object_utils(dec_base_seq)

    // Handle to scoreboard for registering expected results
    dec_scoreboard sb_handle;

    function new(string name = "dec_base_seq");
        super.new(name);
        sb_handle = null;
    endfunction

    // Stub golden model: decoder stub outputs x_in + 1 (clipped INT8).
    // Replace with the full fixed-point model for production regression.
    function void compute_expected(dec_seq_item it);
        for (int i = 0; i < 16; i++) begin
            int v = int'(it.x_in[i]) + 1;
            it.x_out_exp[i] = (v > 127) ? 8'sd127 :
                               (v < -128)? -8'sd128 :
                               ($signed(v[7:0]));
        end
    endfunction

    // Send item to driver and register expected with scoreboard
    task send_item(dec_seq_item it);
        compute_expected(it);
        // Register expected result before driving (ordering guarantee)
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
// dec_prefill_seq — single Prefill transaction (step_id=0)
// =============================================================================
class dec_prefill_seq extends dec_base_seq;
    `uvm_object_utils(dec_prefill_seq)

    // Optionally set x_in values; if not set, uses default (0)
    bit signed [7:0] x_in_override [0:15];
    bit              use_override = 0;

    function new(string name = "dec_prefill_seq");
        super.new(name);
        foreach (x_in_override[i]) x_in_override[i] = 0;
    endfunction

    virtual task body();
        dec_seq_item it = new("prefill_item");
        if (!it.randomize() with { step_id == 0; layer_id == 0; })
            `uvm_fatal("RAND", "dec_prefill_seq: randomization failed")
        if (use_override)
            foreach (x_in_override[i]) it.x_in[i] = x_in_override[i];
        send_item(it);
        `uvm_info("SEQ", "Prefill sequence complete", UVM_MEDIUM)
    endtask

endclass

// =============================================================================
// dec_decode_seq — N sequential decode steps (step_id 1..N)
// =============================================================================
class dec_decode_seq extends dec_base_seq;
    `uvm_object_utils(dec_decode_seq)

    int unsigned n_steps;     // number of decode steps to run
    int unsigned layer_id;    // layer to test (default 0)
    int unsigned start_step;  // starting step_id (default 1)

    function new(string name = "dec_decode_seq");
        super.new(name);
        n_steps    = 4;
        layer_id   = 0;
        start_step = 1;
    endfunction

    virtual task body();
        dec_seq_item it;
        for (int s = 0; s < int'(n_steps); s++) begin
            it = new(
                    $sformatf("dec_item_%0d", s));
            if (!it.randomize() with {
                step_id  == start_step + s;
                layer_id == this.layer_id;
            })
                `uvm_fatal("RAND", "dec_decode_seq: randomization failed")
            send_item(it);
        end
        `uvm_info("SEQ",
            $sformatf("Decode sequence: %0d steps on layer %0d",
                       n_steps, layer_id), UVM_MEDIUM)
    endtask

endclass

// =============================================================================
// dec_rand_seq — fully randomized transactions
// =============================================================================
class dec_rand_seq extends dec_base_seq;
    `uvm_object_utils(dec_rand_seq)

    int unsigned n_txns;   // number of randomized transactions

    function new(string name = "dec_rand_seq");
        super.new(name);
        n_txns = 8;
    endfunction

    virtual task body();
        dec_seq_item it;
        for (int t = 0; t < int'(n_txns); t++) begin
            it = new(
                    $sformatf("rand_item_%0d", t));
            if (!it.randomize())
                `uvm_fatal("RAND", "dec_rand_seq: randomization failed")
            send_item(it);
        end
        `uvm_info("SEQ",
            $sformatf("Random sequence: %0d transactions", n_txns), UVM_MEDIUM)
    endtask

endclass

// =============================================================================
// dec_stress_seq — Prefill + full 255-step autoregressive decode
// =============================================================================
// Simulates the worst-case scenario: a full 256-token generation pass.
// Covers step_id 0..255 on a single layer. Latency grows linearly
// with step (KV read = 32*(s+1) cycles) — the sequence verifies
// that the DUT handles all step indices correctly.
// =============================================================================
class dec_stress_seq extends dec_base_seq;
    `uvm_object_utils(dec_stress_seq)

    int unsigned n_steps;    // default 16 (reduce for simulation speed)
    int unsigned layer_id;

    function new(string name = "dec_stress_seq");
        super.new(name);
        n_steps  = 16;   // 256 for full coverage; 16 for quick regression
        layer_id = 0;
    endfunction

    virtual task body();
        dec_seq_item it;
        // Step 0: Prefill
        it = new("stress_prefill");
        if (!it.randomize() with { step_id == 0; layer_id == this.layer_id; })
            `uvm_fatal("RAND", "dec_stress_seq: prefill rand failed")
        send_item(it);
        // Steps 1..n_steps-1: autoregressive decode
        for (int s = 1; s < int'(n_steps); s++) begin
            it = new(
                    $sformatf("stress_dec_%0d", s));
            if (!it.randomize() with {
                step_id  == s;
                layer_id == this.layer_id;
            })
                `uvm_fatal("RAND", "dec_stress_seq: decode rand failed")
            send_item(it);
        end
        `uvm_info("SEQ",
            $sformatf("Stress sequence: %0d total steps on layer %0d",
                       n_steps, layer_id), UVM_LOW)
    endtask

endclass

`endif // DEC_SEQUENCES_SV
