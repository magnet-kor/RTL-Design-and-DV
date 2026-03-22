// =============================================================================
// riscv_tb_top.sv — RISCV Pipeline UVM Testbench Top
// =============================================================================
// Top-level module:
//   1. Clock generation (100 MHz = 10 ns period)
//   2. Interface instantiation and DUT connection
//   3. Hierarchical memory access (imem load, reg_snapshot update)
//   4. Config DB registration
//   5. run_test() dispatch
//
// Compile command (iverilog):
//   iverilog -g2012 \
//     -DVERILATOR \
//     -I../SCRIPTS/UVM_STUB \
//     ../SCRIPTS/UVM_STUB/uvm_pkg.sv \
//     ../AGENTS/riscv_seq_item.sv \
//     ../AGENTS/riscv_driver.sv \
//     ../AGENTS/riscv_monitor.sv \
//     ../AGENTS/riscv_agent.sv \
//     ../ENV/riscv_scoreboard.sv \
//     ../ENV/riscv_coverage.sv \
//     ../ENV/riscv_env.sv \
//     ../SEQUENCES/riscv_sequences.sv \
//     ../TESTS/riscv_tests.sv \
//     riscv_if.sv \
//     ../../RTL/alu.sv ../../RTL/alu_ctrl.sv \
//     ../../RTL/regfile.sv ../../RTL/imm_gen.sv \
//     ../../RTL/control.sv ../../RTL/forwarding_unit.sv \
//     ../../RTL/hdu.sv ../../RTL/branch_predictor.sv \
//     ../../RTL/riscv_pipeline.sv \
//     riscv_tb_top.sv \
//     -o sim_riscv_uvm && vvp sim_riscv_uvm +UVM_TESTNAME=riscv_rtype_test
//
// Compile command (VCS):
//   vcs -sverilog -ntb_opts uvm-1.2 +define+VCS \
//     [same file list] riscv_tb_top.sv
//   ./simv +UVM_TESTNAME=riscv_regression_test
// =============================================================================
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

`include "../AGENTS/riscv_seq_item.sv"
`include "../AGENTS/riscv_driver.sv"
`include "../AGENTS/riscv_monitor.sv"
`include "../AGENTS/riscv_agent.sv"
`include "../ENV/riscv_scoreboard.sv"
`include "../ENV/riscv_coverage.sv"
`include "../ENV/riscv_env.sv"
`include "../SEQUENCES/riscv_sequences.sv"
`include "../TESTS/riscv_tests.sv"

module riscv_tb_top;

    // ── Clock generation (100 MHz) ────────────────────────────────────────
    localparam CLK_PERIOD = 10;
    logic clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ── Interface ─────────────────────────────────────────────────────────
    riscv_if #(.IMEM_DEPTH(1024)) rif(.clk(clk));

    // ── DUT ───────────────────────────────────────────────────────────────
    riscv_pipeline #(
        .IMEM_DEPTH(1024),
        .DMEM_DEPTH(1024)
    ) dut (
        .clk  (clk),
        .rst_n(rif.rst_n)
    );

    // ── Hierarchical imem load ─────────────────────────────────────────────
    // Monitor rif.imem_wr_en and force DUT imem on write
    always @(posedge rif.imem_wr_en) begin
        dut.imem[rif.imem_wr_addr] = rif.imem_wr_data;
    end

    // ── Register file snapshot update every clock ─────────────────────────
    always @(posedge clk) begin
        for (int i = 0; i < 32; i++) begin
            rif.reg_snapshot[i] = dut.rf.reg_file[i];
        end
    end

    // ── Capture trigger: pulse after driver done_cycles wait ──────────────
    // Driven by riscv_tb_top via UVM config_db event in test
    initial rif.capture_trigger = 0;

    // ── UVM config_db — bind virtual interface ────────────────────────────
    initial begin
        uvm_config_db #(virtual riscv_if)::set(null, "*", "vif", rif);
    end

    // ── Start UVM test ────────────────────────────────────────────────────
    initial begin
        run_test();
    end

    // ── Simulation timeout ────────────────────────────────────────────────
    initial begin
        #5_000_000;
        `uvm_fatal("TB", "Simulation timeout — check pipeline done signal")
    end

endmodule
