// =============================================================================
// riscv_agent.sv — RISCV Pipeline UVM Agent
// =============================================================================
// Active  (UVM_ACTIVE):  driver + sequencer + monitor
// Passive (UVM_PASSIVE): monitor only
//
// Analysis port forwarded from monitor for env-level connectivity.
// =============================================================================
`ifndef RISCV_AGENT_SV
`define RISCV_AGENT_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class riscv_agent extends uvm_agent;
    `uvm_component_utils(riscv_agent)

    riscv_driver                    drv;
    riscv_monitor                   mon;
    uvm_sequencer #(riscv_seq_item) seqr;

    // Forwarded analysis port → env → scoreboard + coverage
    uvm_analysis_port #(riscv_seq_item) ap;

    function new(string name = "riscv_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        ap  = new("ap", this);
        mon = new("mon", this);
        if (is_active == UVM_ACTIVE) begin
            seqr = new("seqr", this);
            drv  = new("drv",  this);
        end
    endfunction

    virtual function void connect_phase(uvm_component phase);
        if (is_active == UVM_ACTIVE)
            drv.seq_item_port.connect(seqr.seq_item_export);
        mon.ap.connect(ap);
    endfunction

endclass
`endif // RISCV_AGENT_SV
