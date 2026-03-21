// =============================================================================
// dec_env.sv — Decoder Layer UVM Environment
// =============================================================================
// Top-level verification environment. Instantiates and connects:
//   dec_agent      — driver + sequencer + monitor
//   dec_axi4_bfm   — AXI4 slave for KV Cache DRAM simulation
//   dec_scoreboard — checks x_out against expected values
//   dec_coverage   — functional coverage collection
//
// Analysis connectivity:
//   monitor.ap → scoreboard.analysis_export
//   monitor.ap → coverage.analysis_export
// =============================================================================
`ifndef DEC_ENV_SV
`define DEC_ENV_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class dec_env extends uvm_env;
    `uvm_component_utils(dec_env)

    dec_agent       agent;
    dec_axi4_bfm    axi_bfm;
    dec_scoreboard  sb;
    dec_coverage    cov;

    function new(string name = "dec_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        agent   = new("agent",   this);
        axi_bfm = new("axi_bfm", this);
        sb      = new("sb",  this);
        cov     = new("cov",   this);
    endfunction

    virtual function void connect_phase(uvm_component phase);
        // Monitor analysis port → scoreboard + coverage
        // Note: analysis_port.connect(analysis_imp) is UVM 1.2 standard
        // For verilator lint, direct write() calls replace the port connection
`ifndef VERILATOR
        agent.ap.connect(sb.analysis_export);
        agent.ap.connect(cov.analysis_export);
`endif
    endfunction

    // Convenience handle to sequencer for test-level sequence starting
    function uvm_sequencer #(dec_seq_item) get_seqr();
        return agent.seqr;
    endfunction

endclass
`endif // DEC_ENV_SV
