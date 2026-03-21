// =============================================================================
// dec_agent.sv — Decoder Layer UVM Agent
// =============================================================================
// Active  (is_active=UVM_ACTIVE):  driver + sequencer + monitor
// Passive (is_active=UVM_PASSIVE): monitor only
//
// Analysis port forwarded from monitor for env-level connectivity.
// =============================================================================
`ifndef DEC_AGENT_SV
`define DEC_AGENT_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class dec_agent extends uvm_agent;
    `uvm_component_utils(dec_agent)

    dec_driver                    drv;
    dec_monitor                   mon;
    uvm_sequencer #(dec_seq_item) seqr;

    // Forwarded analysis port → env → scoreboard + coverage
    uvm_analysis_port #(dec_seq_item) ap;

    function new(string name = "dec_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        ap  = new("ap", this);
        mon = new("mon", this);
        if (is_active == UVM_ACTIVE) begin
            seqr = new("seqr", this);
            drv  = new("drv", this);
        end
    endfunction

    virtual function void connect_phase(uvm_component phase);
        if (is_active == UVM_ACTIVE)
            drv.seq_item_port = seqr; // connect driver to sequencer
        mon.ap.connect(ap);
    endfunction

endclass
`endif // DEC_AGENT_SV
