// =============================================================================
// riscv_env.sv — RISCV Pipeline UVM Environment
// =============================================================================
// Top-level verification environment. Instantiates and connects:
//   riscv_agent      — driver + sequencer + monitor
//   riscv_scoreboard — checks register values against expected
//   riscv_coverage   — functional coverage collection
//
// Analysis connectivity:
//   monitor.ap → scoreboard.analysis_export
//   monitor.ap → coverage.analysis_export
// =============================================================================
`ifndef RISCV_ENV_SV
`define RISCV_ENV_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class riscv_env extends uvm_env;
    `uvm_component_utils(riscv_env)

    riscv_agent      agent;
    riscv_scoreboard sb;
    riscv_coverage   cov;

    function new(string name = "riscv_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        agent = new("agent", this);
        sb    = new("sb",    this);
        cov   = new("cov",   this);
    endfunction

    virtual function void connect_phase(uvm_component phase);
`ifndef VERILATOR
        agent.ap.connect(sb.analysis_export);
        agent.ap.connect(cov.analysis_export);
`endif
    endfunction

    // Convenience accessor for test-level sequence starting
    function uvm_sequencer #(riscv_seq_item) get_seqr();
        return agent.seqr;
    endfunction

endclass
`endif // RISCV_ENV_SV
