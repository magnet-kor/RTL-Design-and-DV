// =============================================================================
// riscv_monitor.sv — RISCV Pipeline UVM Monitor
// =============================================================================
// Passive observer:
//   - Waits for execution signal from driver (via config_db event)
//   - Captures register file snapshot from DUT hierarchy
//   - Publishes riscv_seq_item through analysis port
// Never drives any signals.
// =============================================================================
`ifndef RISCV_MONITOR_SV
`define RISCV_MONITOR_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class riscv_monitor extends uvm_monitor;
    `uvm_component_utils(riscv_monitor)

    virtual riscv_if vif;

    // Analysis port → scoreboard + coverage
    uvm_analysis_port #(riscv_seq_item) ap;

    // Statistics
    int unsigned txn_count;

    function new(string name = "riscv_monitor", uvm_component parent = null);
        super.new(name, parent);
        txn_count = 0;
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual riscv_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "riscv_monitor: no virtual riscv_if in config_db")
    endfunction

    virtual task run_phase(uvm_component phase);
        forever begin
            riscv_seq_item obs;
            // Wait for capture trigger from testbench
            @(posedge vif.capture_trigger);
            @(posedge vif.clk); #1;

            obs           = new("obs");
            obs.end_time  = $time;
            // Capture register file state
            for (int i = 0; i < 32; i++) begin
                obs.regs[i] = vif.reg_snapshot[i];
            end
            ap.write(obs);
            txn_count++;
            `uvm_info("MON",
                $sformatf("Captured reg snapshot #%0d: x1=%0d x2=%0d x3=%0d",
                    txn_count, obs.regs[1], obs.regs[2], obs.regs[3]),
                UVM_MEDIUM)
        end
    endtask

    virtual function void report_phase(uvm_component phase);
        `uvm_info("MON", $sformatf("Total snapshots captured: %0d",
                                    txn_count), UVM_LOW)
    endfunction

endclass
`endif // RISCV_MONITOR_SV
