// =============================================================================
// dec_monitor.sv — Decoder Layer UVM Monitor
// =============================================================================
// Passive observer: watches decoder_if for done=1, captures x_out,
// publishes a dec_seq_item through the analysis port.
// Never drives any signal.
// =============================================================================
`ifndef DEC_MONITOR_SV
`define DEC_MONITOR_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class dec_monitor extends uvm_monitor;
    `uvm_component_utils(dec_monitor)

    virtual decoder_if vif;

    // Analysis port connects to scoreboard + coverage
    uvm_analysis_port #(dec_seq_item) ap;

    // Statistics
    int unsigned txn_count;

    function new(string name = "dec_monitor", uvm_component parent = null);
        super.new(name, parent);
        txn_count = 0;
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual decoder_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "dec_monitor: no virtual decoder_if found in config_db")
    endfunction

    virtual task run_phase(uvm_component phase);
        int i;
        forever begin
            dec_seq_item obs;
            @(posedge vif.clk);
            if (vif.done === 1'b1) begin
                obs           = new("obs");
                obs.done_seen = 1'b1;
                obs.end_time  = $time;
                obs.step_id   = vif.step_id;
                obs.layer_id  = vif.layer_id;
                for (i = 0; i < 16; i++)
                    obs.x_out[i] = vif.x_out[i];
                ap.write(obs);
                txn_count++;
                `uvm_info("MON",
                    $sformatf("Captured done[%0d]: step=%0d x_out[0]=%0d",
                               txn_count, obs.step_id, obs.x_out[0]),
                    UVM_MEDIUM)
            end
        end
    endtask

    virtual function void report_phase(uvm_component phase);
        `uvm_info("MON", $sformatf("Total transactions captured: %0d",
                                    txn_count), UVM_LOW)
    endfunction

endclass
`endif // DEC_MONITOR_SV
