// =============================================================================
// decoder_if.sv — Decoder Layer Verification Interface
// =============================================================================
// Bundles all DUT ports into a single interface for clean testbench/DUT
// connectivity. Parameters match the small stub DUT (HIDDEN=16, DATA_W=8).
// Change HIDDEN to 896 for full decoder_layer.sv integration.
//
// Note: no clocking blocks (avoid iverilog limitation).
// Drivers use @(posedge clk) + #1 skew in task bodies.
// =============================================================================
`ifndef DECODER_IF_SV
`define DECODER_IF_SV
`timescale 1ns/1ps

interface decoder_if #(
    parameter HIDDEN  = 16,
    parameter DATA_W  = 8,
    parameter ADDR_W  = 32,
    parameter DMA_DW  = 64
)(input logic clk);

    // ── Decoder control ──────────────────────────────────────────────────
    logic        rst_n;
    logic        start;
    logic        done;
    logic [7:0]  step_id;
    logic [4:0]  layer_id;

    // ── Activation I/O ───────────────────────────────────────────────────
    logic signed [DATA_W-1:0] x_in  [0:HIDDEN-1];
    logic signed [DATA_W-1:0] x_out [0:HIDDEN-1];

    // ── Weight SRAM — QKV ────────────────────────────────────────────────
    logic [19:0]              qkv_wgt_addr;
    logic signed [DATA_W-1:0] qkv_wgt_rdata;

    // ── Weight SRAM — MHA/FFN ────────────────────────────────────────────
    logic [22:0]              mha_ffn_wgt_addr;
    logic signed [DATA_W-1:0] mha_ffn_wgt_rdata;

    // ── AXI4 Read channel ────────────────────────────────────────────────
    logic [ADDR_W-1:0] ARADDR;
    logic [7:0]        ARLEN;
    logic [2:0]        ARSIZE;
    logic [1:0]        ARBURST;
    logic              ARVALID;
    logic              ARREADY;
    logic [DMA_DW-1:0] RDATA;
    logic              RVALID;
    logic              RLAST;
    logic              RREADY;

    // ── AXI4 Write channel ───────────────────────────────────────────────
    logic [ADDR_W-1:0] AWADDR;
    logic [7:0]        AWLEN;
    logic [2:0]        AWSIZE;
    logic [1:0]        AWBURST;
    logic              AWVALID;
    logic              AWREADY;
    logic [DMA_DW-1:0] WDATA;
    logic              WVALID;
    logic              WLAST;
    logic              WREADY;
    logic              BVALID;
    logic              BREADY;

endinterface
`endif // DECODER_IF_SV
