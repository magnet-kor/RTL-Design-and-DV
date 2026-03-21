// =============================================================================
// dec_driver.sv — Decoder Layer UVM Driver
// =============================================================================
// Pulls dec_seq_item transactions from the sequencer and drives decoder_if.
//
// Protocol (matches decoder_layer.sv DL_IDLE→DL_RMSNORM1 transition):
//   Cycle 0 : assert start=1, set step_id, layer_id, x_in
//   Cycle 1 : deassert start=0
//   (monitor separately watches for done)
//
// Virtual interface is bound via uvm_config_db in the test/env.
// =============================================================================
`ifndef DEC_DRIVER_SV
`define DEC_DRIVER_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class dec_driver extends uvm_driver #(dec_seq_item);
    `uvm_component_utils(dec_driver)

    virtual decoder_if vif;
    // seq_item_port: connected by agent.connect_phase
    uvm_sequencer #(dec_seq_item) seq_item_port;

    function new(string name = "dec_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual decoder_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "dec_driver: no virtual decoder_if found in config_db")
    endfunction

    virtual task run_phase(uvm_component phase);
        dec_seq_item req;
        // Default idle state
        vif.start    <= 0;
        vif.step_id  <= 0;
        vif.layer_id <= 0;
        @(posedge vif.rst_n);   // wait for reset release
        @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(req);
            drive_item(req);
            seq_item_port.item_done();
        end
    endtask

    task drive_item(dec_seq_item it);
        int i;
        @(posedge vif.clk); #1;
        // Pulse start for exactly 1 cycle
        vif.start    <= 1;
        vif.step_id  <= it.step_id[7:0];
        vif.layer_id <= it.layer_id[4:0];
        for (i = 0; i < 16; i++)
            vif.x_in[i] <= it.x_in[i];
        it.start_time = $time;
        @(posedge vif.clk); #1;
        vif.start <= 0;
        `uvm_info("DRV", $sformatf("Drove: %s", it.convert2string()), UVM_HIGH)
    endtask

endclass
`endif // DEC_DRIVER_SV
