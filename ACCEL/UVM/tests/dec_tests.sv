// =============================================================================
// dec_tests.sv — Decoder Layer UVM Tests
// =============================================================================
// All test classes. Each test:
//   1. Binds virtual interface via uvm_config_db
//   2. Builds env (via super.build_phase)
//   3. Creates and starts a sequence in run_phase
//
// Test list:
//   dec_prefill_test  — single Prefill transaction, basic sanity
//   dec_decode_test   — Prefill + 4 decode steps
//   dec_rand_test     — 8 randomized transactions
//   dec_stress_test   — Prefill + 15 decode steps (full coverage target)
// =============================================================================
`ifndef DEC_TESTS_SV
`define DEC_TESTS_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

// =============================================================================
// dec_base_test — base test (reset + env build)
// =============================================================================
class dec_base_test extends uvm_test;
    `uvm_component_utils(dec_base_test)

    dec_env env;

    function new(string name = "dec_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        env = new("env", this);
    endfunction

    // Drive reset sequence (called from run_phase in derived tests)
    task do_reset();
        virtual decoder_if vif_local;
        if (!uvm_config_db #(virtual decoder_if)::get(
                this, "", "vif", vif_local))
            `uvm_fatal("NOVIF", "dec_base_test: no vif in config_db")
        vif_local.rst_n   <= 0;
        vif_local.start   <= 0;
        vif_local.step_id <= 0;
        vif_local.layer_id<= 0;
        repeat (6) @(posedge vif_local.clk);
        #1;
        vif_local.rst_n <= 1;
        @(posedge vif_local.clk);
        `uvm_info("TEST", "Reset deasserted", UVM_MEDIUM)
    endtask

    virtual function void report_phase(uvm_component phase);
        uvm_report_server srv = uvm_report_server::get_server();
        if (srv.get_severity_count(UVM_ERROR)   == 0 &&
            srv.get_severity_count(UVM_FATAL)   == 0) begin
            `uvm_info("TEST",
                "==============================================", UVM_NONE)
            `uvm_info("TEST", "  *** TEST PASSED ***", UVM_NONE)
            `uvm_info("TEST",
                "==============================================", UVM_NONE)
        end else begin
            `uvm_error("TEST",
                $sformatf("  *** TEST FAILED: %0d errors ***",
                    srv.get_severity_count(UVM_ERROR)))
        end
    endfunction

endclass

// =============================================================================
// dec_prefill_test — single Prefill, basic connectivity check
// =============================================================================
class dec_prefill_test extends dec_base_test;
    `uvm_component_utils(dec_prefill_test)

    function new(string name = "dec_prefill_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_component phase);
        dec_prefill_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting dec_prefill_test", UVM_LOW)
        do_reset();
        seq           = new("seq");
        seq.sb_handle = env.sb;
        seq.start(env.get_seqr());
        // Allow monitor to capture done
        repeat (50) @(posedge env.agent.mon.vif.clk);
        phase.drop_objection(this);
    endtask

endclass

// =============================================================================
// dec_decode_test — Prefill + 4 decode steps
// =============================================================================
class dec_decode_test extends dec_base_test;
    `uvm_component_utils(dec_decode_test)

    function new(string name = "dec_decode_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_component phase);
        dec_prefill_seq pre_seq;
        dec_decode_seq  dec_seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting dec_decode_test", UVM_LOW)
        do_reset();
        // Prefill
        pre_seq           = new("pre_seq");
        pre_seq.sb_handle = env.sb;
        pre_seq.start(env.get_seqr());
        repeat (30) @(posedge env.agent.mon.vif.clk);
        // 4 decode steps
        dec_seq           = new("dec_seq");
        dec_seq.sb_handle = env.sb;
        dec_seq.n_steps   = 4;
        dec_seq.layer_id  = 0;
        dec_seq.start_step = 1;
        dec_seq.start(env.get_seqr());
        repeat (200) @(posedge env.agent.mon.vif.clk);
        phase.drop_objection(this);
    endtask

endclass

// =============================================================================
// dec_rand_test — 8 fully randomized transactions
// =============================================================================
class dec_rand_test extends dec_base_test;
    `uvm_component_utils(dec_rand_test)

    function new(string name = "dec_rand_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_component phase);
        dec_rand_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting dec_rand_test", UVM_LOW)
        do_reset();
        seq           = new("seq");
        seq.sb_handle = env.sb;
        seq.n_txns    = 8;
        seq.start(env.get_seqr());
        repeat (500) @(posedge env.agent.mon.vif.clk);
        phase.drop_objection(this);
    endtask

endclass

// =============================================================================
// dec_stress_test — Prefill + 15 autoregressive steps, all layers
// =============================================================================
class dec_stress_test extends dec_base_test;
    `uvm_component_utils(dec_stress_test)

    function new(string name = "dec_stress_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_component phase);
        dec_stress_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting dec_stress_test (16 steps)", UVM_LOW)
        do_reset();
        for (int l = 0; l < 3; l++) begin   // test 3 layers: 0, 1, 2
            seq           = new(
                                $sformatf("stress_l%0d", l));
            seq.sb_handle = env.sb;
            seq.n_steps   = 16;
            seq.layer_id  = l;
            seq.start(env.get_seqr());
            repeat (100) @(posedge env.agent.mon.vif.clk);
        end
        repeat (1000) @(posedge env.agent.mon.vif.clk);
        phase.drop_objection(this);
    endtask

endclass

`endif // DEC_TESTS_SV
