// =============================================================================
// riscv_tests.sv — RISCV Pipeline UVM Tests
// =============================================================================
// Test list:
//   riscv_base_test      — base: reset, env build
//   riscv_rtype_test     — R-type ALU instructions
//   riscv_itype_test     — I-type immediate ALU
//   riscv_load_test      — Load/Store round-trip
//   riscv_branch_test    — Branch instructions (BEQ/BNE)
//   riscv_jal_test       — JAL jump-and-link
//   riscv_hazard_test    — Data hazard / forwarding chain
//   riscv_regression_test — Full regression (all sequences)
// =============================================================================
`ifndef RISCV_TESTS_SV
`define RISCV_TESTS_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

// =============================================================================
// riscv_base_test
// =============================================================================
class riscv_base_test extends uvm_test;
    `uvm_component_utils(riscv_base_test)

    riscv_env env;

    function new(string name = "riscv_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        env = new("env", this);
    endfunction

    virtual function void report_phase(uvm_component phase);
        uvm_report_server srv = uvm_report_server::get_server();
        if (srv.get_severity_count(UVM_ERROR) == 0 &&
            srv.get_severity_count(UVM_FATAL) == 0) begin
            `uvm_info("TEST", "==============================================", UVM_NONE)
            `uvm_info("TEST", "  *** TEST PASSED ***",                         UVM_NONE)
            `uvm_info("TEST", "==============================================", UVM_NONE)
        end else begin
            `uvm_error("TEST", $sformatf("  *** TEST FAILED: %0d errors ***",
                srv.get_severity_count(UVM_ERROR)))
        end
    endfunction

endclass

// =============================================================================
// riscv_rtype_test
// =============================================================================
class riscv_rtype_test extends riscv_base_test;
    `uvm_component_utils(riscv_rtype_test)

    function new(string name = "riscv_rtype_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_component phase);
        riscv_rtype_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting riscv_rtype_test", UVM_LOW)
        seq           = new("seq");
        seq.sb_handle = env.sb;
        seq.start(env.get_seqr());
        phase.drop_objection(this);
    endtask

endclass

// =============================================================================
// riscv_itype_test
// =============================================================================
class riscv_itype_test extends riscv_base_test;
    `uvm_component_utils(riscv_itype_test)

    function new(string name = "riscv_itype_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_component phase);
        riscv_itype_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting riscv_itype_test", UVM_LOW)
        seq           = new("seq");
        seq.sb_handle = env.sb;
        seq.start(env.get_seqr());
        phase.drop_objection(this);
    endtask

endclass

// =============================================================================
// riscv_load_test
// =============================================================================
class riscv_load_test extends riscv_base_test;
    `uvm_component_utils(riscv_load_test)

    function new(string name = "riscv_load_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_component phase);
        riscv_load_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting riscv_load_test", UVM_LOW)
        seq           = new("seq");
        seq.sb_handle = env.sb;
        seq.start(env.get_seqr());
        phase.drop_objection(this);
    endtask

endclass

// =============================================================================
// riscv_branch_test
// =============================================================================
class riscv_branch_test extends riscv_base_test;
    `uvm_component_utils(riscv_branch_test)

    function new(string name = "riscv_branch_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_component phase);
        riscv_branch_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting riscv_branch_test", UVM_LOW)
        seq           = new("seq");
        seq.sb_handle = env.sb;
        seq.start(env.get_seqr());
        phase.drop_objection(this);
    endtask

endclass

// =============================================================================
// riscv_jal_test
// =============================================================================
class riscv_jal_test extends riscv_base_test;
    `uvm_component_utils(riscv_jal_test)

    function new(string name = "riscv_jal_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_component phase);
        riscv_jal_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting riscv_jal_test", UVM_LOW)
        seq           = new("seq");
        seq.sb_handle = env.sb;
        seq.start(env.get_seqr());
        phase.drop_objection(this);
    endtask

endclass

// =============================================================================
// riscv_hazard_test
// =============================================================================
class riscv_hazard_test extends riscv_base_test;
    `uvm_component_utils(riscv_hazard_test)

    function new(string name = "riscv_hazard_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_component phase);
        riscv_hazard_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting riscv_hazard_test", UVM_LOW)
        seq           = new("seq");
        seq.sb_handle = env.sb;
        seq.start(env.get_seqr());
        phase.drop_objection(this);
    endtask

endclass

// =============================================================================
// riscv_regression_test
// =============================================================================
class riscv_regression_test extends riscv_base_test;
    `uvm_component_utils(riscv_regression_test)

    function new(string name = "riscv_regression_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_component phase);
        riscv_regression_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting riscv_regression_test", UVM_LOW)
        seq           = new("seq");
        seq.sb_handle = env.sb;
        seq.start(env.get_seqr());
        phase.drop_objection(this);
    endtask

endclass

`endif // RISCV_TESTS_SV
