// =============================================================================
// dec_tb_top.sv — Decoder Layer UVM Testbench Top
// =============================================================================
// Top-level module for UVM simulation:
//   1. Clock generation (100 MHz for stub; change to 200 MHz for full DUT)
//   2. Interface instantiation and DUT port binding
//   3. Config DB interface registration
//   4. run_test() dispatch (test name via +UVM_TESTNAME plusarg)
//
// Compile command (Questa):
//   vlog -sv -mfcu +define+QUESTA \
//     -I<uvm_stub_dir> <uvm_stub_dir>/uvm_pkg.sv \
//     agents/dec_seq_item.sv agents/dec_driver.sv \
//     agents/dec_monitor.sv  agents/dec_agent.sv  \
//     env/dec_scoreboard.sv  env/dec_coverage.sv  \
//     env/dec_axi4_bfm.sv    env/dec_env.sv       \
//     sequences/dec_sequences.sv                  \
//     tests/dec_tests.sv                          \
//     tb/decoder_if.sv tb/decoder_layer_stub.sv   \
//     tb/dec_tb_top.sv
//   vsim dec_tb_top +UVM_TESTNAME=dec_decode_test
//
// Compile command (VCS):
//   vcs -sverilog -ntb_opts uvm-1.2 +define+VCS \
//     [same file list] dec_tb_top.sv
//   ./simv +UVM_TESTNAME=dec_decode_test
//
// Lint command (verilator):
//   see scripts/run_lint.sh
// =============================================================================
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

`include "agents/dec_seq_item.sv"
`include "agents/dec_driver.sv"
`include "agents/dec_monitor.sv"
`include "agents/dec_agent.sv"
`include "env/dec_scoreboard.sv"
`include "env/dec_coverage.sv"
`include "env/dec_axi4_bfm.sv"
`include "env/dec_env.sv"
`include "sequences/dec_sequences.sv"
`include "tests/dec_tests.sv"

module dec_tb_top;

    // ── Clock generation ─────────────────────────────────────────────────
    // 100 MHz (10 ns) for stub simulation. Change to 5 ns for full DUT.
    localparam CLK_PERIOD = 10;
    logic clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ── Interface ─────────────────────────────────────────────────────────
    decoder_if #(.HIDDEN(16), .DATA_W(8)) dif(.clk(clk));

    // ── DUT — stub (replace with decoder_layer for full regression) ───────
    decoder_layer_stub #(
        .HIDDEN  (16),
        .DATA_W  (8),
        .LATENCY (20)
    ) dut (
        .clk              (clk),
        .rst_n            (dif.rst_n),
        .start            (dif.start),
        .done             (dif.done),
        .step_id          (dif.step_id),
        .layer_id         (dif.layer_id),
        .x_in             (dif.x_in),
        .x_out            (dif.x_out),
        .qkv_wgt_addr     (dif.qkv_wgt_addr),
        .qkv_wgt_rdata    (dif.qkv_wgt_rdata),
        .mha_ffn_wgt_addr (dif.mha_ffn_wgt_addr),
        .mha_ffn_wgt_rdata(dif.mha_ffn_wgt_rdata),
        .ARADDR           (dif.ARADDR),  .ARLEN   (dif.ARLEN),
        .ARSIZE           (dif.ARSIZE),  .ARBURST (dif.ARBURST),
        .ARVALID          (dif.ARVALID), .ARREADY (dif.ARREADY),
        .RDATA            (dif.RDATA),   .RVALID  (dif.RVALID),
        .RLAST            (dif.RLAST),   .RREADY  (dif.RREADY),
        .AWADDR           (dif.AWADDR),  .AWLEN   (dif.AWLEN),
        .AWSIZE           (dif.AWSIZE),  .AWBURST (dif.AWBURST),
        .AWVALID          (dif.AWVALID), .AWREADY (dif.AWREADY),
        .WDATA            (dif.WDATA),   .WVALID  (dif.WVALID),
        .WLAST            (dif.WLAST),   .WREADY  (dif.WREADY),
        .BVALID           (dif.BVALID),  .BREADY  (dif.BREADY)
    );

    // ── UVM config_db — bind virtual interface ────────────────────────────
    initial begin
        uvm_config_db #(virtual decoder_if)::set(null, "*", "vif", dif);
    end

    // ── Start UVM test ────────────────────────────────────────────────────
    initial begin
        run_test();   // test name via +UVM_TESTNAME; default: dec_decode_test
    end

    // ── Simulation timeout guard ──────────────────────────────────────────
    initial begin
        #10_000_000;   // 10 ms stub simulation limit
        `uvm_fatal("TB", "Simulation timeout — check DUT done signal")
    end

endmodule
