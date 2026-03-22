// =============================================================================
// riscv_driver.sv — RISCV Pipeline UVM Driver
// =============================================================================
// Drives riscv_seq_item transactions:
//   1. Assert rst_n=0 for RESET_CYCLES cycles
//   2. Load program[] into DUT imem via hierarchical force
//   3. Deassert rst_n=1 to start execution
//   4. Wait done_cycles cycles for pipeline to complete
//
// Virtual interface bound via uvm_config_db in test/env.
// =============================================================================
`ifndef RISCV_DRIVER_SV
`define RISCV_DRIVER_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class riscv_driver extends uvm_driver #(riscv_seq_item);
    `uvm_component_utils(riscv_driver)

    virtual riscv_if vif;

    localparam RESET_CYCLES = 6;

    function new(string name = "riscv_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual riscv_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "riscv_driver: no virtual riscv_if in config_db")
    endfunction

    virtual task run_phase(uvm_component phase);
        riscv_seq_item req;
        // Hold reset
        vif.rst_n <= 0;
        repeat (RESET_CYCLES) @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(req);
            drive_item(req);
            seq_item_port.item_done();
        end
    endtask

    task drive_item(riscv_seq_item it);
        // Assert reset
        vif.rst_n <= 0;
        repeat (RESET_CYCLES) @(posedge vif.clk);

        // Load program into imem via hierarchical access
        for (int i = 0; i < it.program_mem.size(); i++) begin
            vif.load_imem(i, it.program_mem[i]);
        end
        // NOP-fill remaining imem
        for (int i = it.program_mem.size(); i < 16; i++) begin
            vif.load_imem(i, 32'h00000013); // NOP (addi x0,x0,0)
        end

        it.start_time = $time;
        `uvm_info("DRV", $sformatf("Loaded %0d instructions, releasing reset",
            it.program_mem.size()), UVM_MEDIUM)

        // Release reset and let pipeline run
        @(posedge vif.clk); #1;
        vif.rst_n <= 1;

        // Wait for program completion
        repeat (it.done_cycles) @(posedge vif.clk);
        it.end_time = $time;

        `uvm_info("DRV", $sformatf("Done: %s (%0d cycles)",
            it.convert2string(), it.latency_cycles()), UVM_HIGH)
    endtask

endclass
`endif // RISCV_DRIVER_SV
