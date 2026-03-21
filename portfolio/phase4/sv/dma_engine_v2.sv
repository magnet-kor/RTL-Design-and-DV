// =============================================================================
// dma_engine_v2.sv — AXI4 Master DMA with Bidirectional Channels
// =============================================================================
// Read channel (DRAM → on-chip SRAM): inherited from NPU phase.
// Write channel (on-chip SRAM → DRAM): added for KV cache write-back.
//
// AXI4 burst parameters: ARLEN/AWLEN=15 (16 beats × 8 B = 128 B/burst)
// Read and Write FSMs are fully independent (AXI4 channels are orthogonal).
// SRAM port separation: read DMA uses SRAM write port, write DMA uses read port.
// =============================================================================
`timescale 1ns/1ps

module dma_engine_v2 #(
    parameter ADDR_W  = 32,
    parameter DATA_W  = 64,
    parameter BURST   = 16,
    parameter SRAM_AW = 18
)(
    input  logic                  clk, rst_n,
    // Read control
    input  logic                  rd_start,
    input  logic [ADDR_W-1:0]     rd_dram_addr,
    input  logic [SRAM_AW-1:0]    rd_sram_addr,
    input  logic [15:0]           rd_len_bytes,
    output logic                  rd_done,
    // Write control
    input  logic                  wr_start,
    input  logic [ADDR_W-1:0]     wr_dram_addr,
    input  logic [SRAM_AW-1:0]    wr_sram_addr,
    input  logic [15:0]           wr_len_bytes,
    output logic                  wr_done,
    // AXI4 Read
    output logic [ADDR_W-1:0]     ARADDR,
    output logic [7:0]            ARLEN,
    output logic [2:0]            ARSIZE,
    output logic [1:0]            ARBURST,
    output logic                  ARVALID,
    input  logic                  ARREADY,
    input  logic [DATA_W-1:0]     RDATA,
    input  logic                  RVALID, RLAST,
    output logic                  RREADY,
    // AXI4 Write
    output logic [ADDR_W-1:0]     AWADDR,
    output logic [7:0]            AWLEN,
    output logic [2:0]            AWSIZE,
    output logic [1:0]            AWBURST,
    output logic                  AWVALID,
    input  logic                  AWREADY,
    output logic [DATA_W-1:0]     WDATA,
    output logic                  WVALID, WLAST,
    input  logic                  WREADY,
    input  logic                  BVALID,
    output logic                  BREADY,
    // SRAM — write port (populated by read DMA)
    output logic [SRAM_AW-1:0]    sram_waddr,
    output logic [DATA_W-1:0]     sram_wdata,
    output logic                  sram_wen,
    // SRAM — read port (consumed by write DMA)
    output logic [SRAM_AW-1:0]    sram_raddr,
    input  logic [DATA_W-1:0]     sram_rdata
);
    localparam BPB = DATA_W / 8;   // bytes per beat = 8

    // ── Read FSM ──────────────────────────────────────────────────────────
    typedef enum logic [1:0] { RD_IDLE, RD_AR, RD_DATA, RD_DONE } rd_t;
    rd_t rd_state;
    logic [ADDR_W-1:0]  rd_addr_r;
    logic [15:0]        rd_remain;
    logic [SRAM_AW-1:0] rd_sptr;

    // Use wire+assign to avoid NBA conflicts on combinatorial signals
    wire  [DATA_W-1:0]  rdata_w   = RDATA;
    wire                rlast_w   = RLAST;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state<=RD_IDLE; rd_done<=0; ARVALID<=0; RREADY<=0; sram_wen<=0;
        end else begin
            rd_done<=0; sram_wen<=0;
            case(rd_state)
                RD_IDLE: if(rd_start) begin
                    rd_addr_r<=rd_dram_addr; rd_remain<=rd_len_bytes;
                    rd_sptr<=rd_sram_addr; rd_state<=RD_AR;
                end
                RD_AR: begin
                    ARADDR<=rd_addr_r; ARLEN<=BURST-1; ARSIZE<=3'd3;
                    ARBURST<=2'b01; ARVALID<=1;
                    if(ARREADY) begin ARVALID<=0; RREADY<=1; rd_state<=RD_DATA; end
                end
                RD_DATA: if(RVALID) begin
                    sram_waddr<=rd_sptr; sram_wdata<=rdata_w; sram_wen<=1;
                    rd_sptr<=rd_sptr+1;
                    if(rlast_w) begin
                        RREADY<=0;
                        rd_addr_r<=rd_addr_r+BURST*BPB;
                        rd_remain<=rd_remain-BURST*BPB;
                        rd_state<=(rd_remain<=BURST*BPB)?RD_DONE:RD_AR;
                    end
                end
                RD_DONE: begin rd_done<=1; rd_state<=RD_IDLE; end
            endcase
        end
    end

    // ── Write FSM ─────────────────────────────────────────────────────────
    typedef enum logic [2:0] { WR_IDLE, WR_AW, WR_DATA, WR_RESP, WR_DONE } wr_t;
    wr_t wr_state;
    logic [ADDR_W-1:0]  wr_addr_r;
    logic [15:0]        wr_remain;
    logic [SRAM_AW-1:0] wr_sptr;
    logic [7:0]         wr_beat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state<=WR_IDLE; wr_done<=0; AWVALID<=0; WVALID<=0; WLAST<=0; BREADY<=0;
        end else begin
            wr_done<=0;
            case(wr_state)
                WR_IDLE: if(wr_start) begin
                    wr_addr_r<=wr_dram_addr; wr_remain<=wr_len_bytes;
                    wr_sptr<=wr_sram_addr; wr_state<=WR_AW;
                end
                WR_AW: begin
                    AWADDR<=wr_addr_r; AWLEN<=BURST-1; AWSIZE<=3'd3;
                    AWBURST<=2'b01; AWVALID<=1;
                    if(AWREADY) begin
                        AWVALID<=0; wr_beat<=0;
                        sram_raddr<=wr_sptr; wr_state<=WR_DATA;
                    end
                end
                WR_DATA: begin
                    WVALID<=1; WDATA<=sram_rdata;
                    WLAST<=(wr_beat==BURST-1);
                    if(WREADY) begin
                        wr_beat<=wr_beat+1;
                        wr_sptr<=wr_sptr+1;
                        sram_raddr<=wr_sptr+1;
                        if(wr_beat==BURST-1) begin
                            WVALID<=0; WLAST<=0;
                            wr_addr_r<=wr_addr_r+BURST*BPB;
                            wr_remain<=wr_remain-BURST*BPB;
                            BREADY<=1; wr_state<=WR_RESP;
                        end
                    end
                end
                WR_RESP: if(BVALID) begin
                    BREADY<=0;
                    wr_state<=(wr_remain<=BURST*BPB)?WR_DONE:WR_AW;
                end
                WR_DONE: begin wr_done<=1; wr_state<=WR_IDLE; end
                default: wr_state<=WR_IDLE;
            endcase
        end
    end
endmodule
