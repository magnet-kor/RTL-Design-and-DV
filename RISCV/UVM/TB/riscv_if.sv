// =============================================================================
// riscv_if.sv — RISCV Pipeline Verification Interface
// =============================================================================
// Provides clock, reset, and testbench-controlled signals.
// Internal DUT memories are accessed via hierarchical reference in TB top.
//
// load_imem(): task called by driver to inject instructions
// reg_snapshot[]: populated by TB top each clock via hierarchical read
// capture_trigger: pulsed by TB when pipeline execution is complete
// =============================================================================
`ifndef RISCV_IF_SV
`define RISCV_IF_SV
`timescale 1ns/1ps

interface riscv_if #(
    parameter IMEM_DEPTH = 1024,
    parameter DATA_W     = 32
)(input logic clk);

    // ── Control signals ──────────────────────────────────────────────────
    logic rst_n;

    // ── Register file snapshot (populated by TB top via hierarchy) ───────
    logic [DATA_W-1:0] reg_snapshot [32];

    // ── Capture trigger: pulsed when execution done ───────────────────────
    logic capture_trigger;

    // ── Task: load one instruction word into DUT imem ─────────────────────
    // Note: implemented in TB top via force statements on DUT hierarchy.
    // This task writes to the interface's internal shadow copy that TB
    // top monitors to drive the hierarchical force.
    logic [31:0]  imem_wr_data;
    logic [31:0]  imem_wr_addr;
    logic         imem_wr_en;

    task load_imem(input int addr, input logic [31:0] data);
        imem_wr_addr = addr;
        imem_wr_data = data;
        imem_wr_en   = 1;
        #1;
        imem_wr_en   = 0;
    endtask

endinterface
`endif // RISCV_IF_SV
