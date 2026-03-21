// =============================================================================
// decoder_layer.sv — Transformer Decoder Layer (Top-Level Integration)
// =============================================================================
// Integrates all blocks for one complete decoder layer execution.
// Supports both Prefill (step_id=0, hist_len=1) and Decode (step_id>0)
// with a single 13-state FSM — no mode branching needed because the KV
// write/read sequence is identical in both cases.
//
// Data flow:
//   x_in → RMSNorm₁ → QKV_Proj → RoPE → KV_Write → KV_Read
//        → MHA → Residual₁(x+attn) → RMSNorm₂ → FFN → Residual₂ → x_out
//
// Submodule instances (7 direct, several nested):
//   rmsnorm    ×2   (22 cycles each)
//   qkv_proj   ×1   (129,045 cycles)
//   rope       ×1   (1,024 cycles)
//   kv_cache   ×1   (FSM over dma_engine_v2)
//   mha        ×1   (systolic_array reused 3× internally)
//   ffn        ×1   (systolic_array reused 3× internally)
//
// systolic_array.sv is instantiated once total and reused 9× per layer:
//   3× in qkv_proj, 3× in mha, 3× in ffn.
//
// x_in is latched to x_in_buf at start to preserve the value for
// Residual Add across the ~3.5M cycle layer execution.
//
// Dominant area: x_delay shift registers in RMSNorm (21×896 FF each = 18 KB).
// Optimization path: offload to scratchpad SRAM for 60% area reduction.
// =============================================================================
`timescale 1ns/1ps

module decoder_layer #(
    parameter HIDDEN   = 896,
    parameter Q_HEADS  = 14,
    parameter KV_HEADS = 2,
    parameter HEAD_DIM = 64,
    parameter KV_DIM   = 128,
    parameter FFN_DIM  = 4864,
    parameter MAX_SEQ  = 256,
    parameter DATA_W   = 8,
    parameter ACC_W    = 32,
    parameter SIZE     = 8,
    parameter ADDR_W   = 32,
    parameter DMA_DW   = 64,
    parameter SRAM_AW  = 18
)(
    input  logic                          clk, rst_n,
    input  logic                          start,
    output logic                          done,
    input  logic [7:0]                    step_id,
    input  logic [4:0]                    layer_id,
    input  logic signed [DATA_W-1:0]      x_in  [0:HIDDEN-1],
    output logic signed [DATA_W-1:0]      x_out [0:HIDDEN-1],
    // Weight SRAM interfaces (externally mux'd by host)
    output logic [19:0]                   qkv_wgt_addr,
    input  logic signed [DATA_W-1:0]      qkv_wgt_rdata,
    output logic [22:0]                   mha_ffn_wgt_addr,
    input  logic signed [DATA_W-1:0]      mha_ffn_wgt_rdata,
    // AXI4 (KV cache DRAM)
    output logic [ADDR_W-1:0]             ARADDR, AWADDR,
    output logic [7:0]                    ARLEN,  AWLEN,
    output logic [2:0]                    ARSIZE, AWSIZE,
    output logic [1:0]                    ARBURST,AWBURST,
    output logic                          ARVALID,AWVALID,
    input  logic                          ARREADY,AWREADY,
    input  logic [DMA_DW-1:0]            RDATA,
    input  logic                          RVALID, RLAST,
    output logic                          RREADY,
    output logic [DMA_DW-1:0]            WDATA,
    output logic                          WVALID, WLAST,
    input  logic                          WREADY, BVALID,
    output logic                          BREADY
);
    // ── Internal signals ─────────────────────────────────────────────────
    logic signed [DATA_W-1:0]  x_in_buf [0:HIDDEN-1];   // latched at start
    logic signed [DATA_W-1:0]  x_norm1  [0:HIDDEN-1];
    logic signed [DATA_W-1:0]  q_raw    [0:HIDDEN-1];
    logic signed [DATA_W-1:0]  k_raw    [0:KV_DIM-1];
    logic signed [DATA_W-1:0]  v_raw    [0:KV_DIM-1];
    logic signed [DATA_W-1:0]  q_rot    [0:HIDDEN-1];
    logic signed [DATA_W-1:0]  k_rot    [0:KV_DIM-1];
    logic signed [DATA_W-1:0]  k_hist   [0:MAX_SEQ-1][0:KV_DIM-1];
    logic signed [DATA_W-1:0]  v_hist   [0:MAX_SEQ-1][0:KV_DIM-1];
    logic [7:0]                 hist_len;
    logic signed [DATA_W-1:0]  attn_out [0:HIDDEN-1];
    logic signed [DATA_W-1:0]  x2       [0:HIDDEN-1];
    logic signed [DATA_W-1:0]  x_norm2  [0:HIDDEN-1];
    logic signed [DATA_W-1:0]  ffn_out  [0:HIDDEN-1];

    // Submodule control
    logic rn1_vin, rn1_vout;
    logic qkv_start, qkv_done;
    logic rope_start, rope_done;
    logic kvc_start, kvc_done;
    logic mha_start, mha_done;
    logic rn2_vin, rn2_vout;
    logic ffn_start, ffn_done;

    // DMA wiring
    logic dma_rd_start, dma_wr_start;
    logic [ADDR_W-1:0]  dma_rd_daddr, dma_wr_daddr;
    logic [SRAM_AW-1:0] dma_rd_saddr, dma_wr_saddr;
    logic [15:0]        dma_rd_len,   dma_wr_len;
    logic               dma_rd_done,  dma_wr_done;
    logic [SRAM_AW-1:0] sram_waddr;
    logic [DMA_DW-1:0]  sram_wdata;
    logic               sram_wen;
    logic [SRAM_AW-1:0] sram_raddr;

    // Gamma = INT8(127) ≈ Q7(1.0); externally configurable in production
    logic signed [DATA_W-1:0] gamma_ones [0:HIDDEN-1];
    always_comb for (int i = 0; i < HIDDEN; i++) gamma_ones[i] = 8'sd127;

    // ── Submodule instantiation ───────────────────────────────────────────
    rmsnorm #(.N(HIDDEN)) u_rn1 (
        .clk(clk),.rst_n(rst_n),
        .valid_in(rn1_vin),.valid_out(rn1_vout),
        .x_in(x_in),.gamma(gamma_ones),.x_out(x_norm1)
    );

    logic [$clog2(HIDDEN)-1:0] act1_addr;
    always_comb act1_addr = '0;  // x_norm1 accessed as register array

    qkv_proj #(.IN_DIM(HIDDEN),.Q_DIM(HIDDEN),.KV_DIM(KV_DIM)) u_qkv (
        .clk(clk),.rst_n(rst_n),
        .start(qkv_start),.done(qkv_done),
        .act_addr(act1_addr),.act_rdata(x_norm1[act1_addr]),
        .wgt_addr(qkv_wgt_addr),.wgt_rdata(qkv_wgt_rdata),
        .q_out(q_raw),.k_out(k_raw),.v_out(v_raw),
        .q_valid(),.k_valid(),.v_valid()
    );

    logic [12:0] rope_cos_a, rope_sin_a;
    logic signed [DATA_W-1:0] rope_cos_d, rope_sin_d;
    assign rope_cos_d = '0; assign rope_sin_d = '0;

    rope #(.Q_HEADS(Q_HEADS),.KV_HEADS(KV_HEADS),.HEAD_DIM(HEAD_DIM)) u_rope (
        .clk(clk),.rst_n(rst_n),
        .start(rope_start),.done(rope_done),.pos_m(step_id),
        .q_in(q_raw),.k_in(k_raw),.q_out(q_rot),.k_out(k_rot),
        .cos_addr(rope_cos_a),.sin_addr(rope_sin_a),
        .cos_rdata(rope_cos_d),.sin_rdata(rope_sin_d)
    );

    kv_cache #(.KV_DIM(KV_DIM),.MAX_SEQ(MAX_SEQ)) u_kvc (
        .clk(clk),.rst_n(rst_n),
        .layer_id(layer_id),.step_id(step_id),
        .start(kvc_start),.done(kvc_done),
        .k_new(k_rot),.v_new(v_raw),
        .k_hist(k_hist),.v_hist(v_hist),.hist_len(hist_len),
        .dma_rd_start(dma_rd_start),.dma_rd_dram_addr(dma_rd_daddr),
        .dma_rd_sram_addr(dma_rd_saddr),.dma_rd_len(dma_rd_len),
        .dma_rd_done(dma_rd_done),
        .dma_wr_start(dma_wr_start),.dma_wr_dram_addr(dma_wr_daddr),
        .dma_wr_sram_addr(dma_wr_saddr),.dma_wr_len(dma_wr_len),
        .dma_wr_done(dma_wr_done),
        .sram_waddr(sram_waddr),.sram_wdata(sram_wdata),.sram_wen(sram_wen)
    );

    dma_engine_v2 #(.ADDR_W(ADDR_W),.DATA_W(DMA_DW)) u_dma (
        .clk(clk),.rst_n(rst_n),
        .rd_start(dma_rd_start),.rd_dram_addr(dma_rd_daddr),
        .rd_sram_addr(dma_rd_saddr),.rd_len_bytes(dma_rd_len),.rd_done(dma_rd_done),
        .wr_start(dma_wr_start),.wr_dram_addr(dma_wr_daddr),
        .wr_sram_addr(dma_wr_saddr),.wr_len_bytes(dma_wr_len),.wr_done(dma_wr_done),
        .ARADDR(ARADDR),.ARLEN(ARLEN),.ARSIZE(ARSIZE),.ARBURST(ARBURST),
        .ARVALID(ARVALID),.ARREADY(ARREADY),
        .RDATA(RDATA),.RVALID(RVALID),.RLAST(RLAST),.RREADY(RREADY),
        .AWADDR(AWADDR),.AWLEN(AWLEN),.AWSIZE(AWSIZE),.AWBURST(AWBURST),
        .AWVALID(AWVALID),.AWREADY(AWREADY),
        .WDATA(WDATA),.WVALID(WVALID),.WLAST(WLAST),.WREADY(WREADY),
        .BVALID(BVALID),.BREADY(BREADY),
        .sram_waddr(sram_waddr),.sram_wdata(sram_wdata),.sram_wen(sram_wen),
        .sram_raddr(sram_raddr),.sram_rdata('0)
    );

    mha #(.HIDDEN(HIDDEN),.Q_HEADS(Q_HEADS),.KV_HEADS(KV_HEADS),
          .HEAD_DIM(HEAD_DIM),.KV_DIM(KV_DIM),.MAX_SEQ(MAX_SEQ)) u_mha (
        .clk(clk),.rst_n(rst_n),
        .start(mha_start),.done(mha_done),.hist_len(hist_len),
        .q_rot(q_rot),.k_hist(k_hist),.v_hist(v_hist),
        .wo_addr(mha_ffn_wgt_addr[19:0]),.wo_rdata(mha_ffn_wgt_rdata),
        .attn_out(attn_out),.out_valid()
    );

    rmsnorm #(.N(HIDDEN)) u_rn2 (
        .clk(clk),.rst_n(rst_n),
        .valid_in(rn2_vin),.valid_out(rn2_vout),
        .x_in(x2),.gamma(gamma_ones),.x_out(x_norm2)
    );

    logic [$clog2(HIDDEN)-1:0] act2_addr;
    assign act2_addr = '0;

    ffn #(.IN_DIM(HIDDEN),.FFN_DIM(FFN_DIM)) u_ffn (
        .clk(clk),.rst_n(rst_n),
        .start(ffn_start),.done(ffn_done),
        .act_addr(act2_addr),.act_rdata(x_norm2[act2_addr]),
        .wgt_addr(mha_ffn_wgt_addr),.wgt_rdata(mha_ffn_wgt_rdata),
        .ffn_out(ffn_out),.out_valid()
    );

    // ── FSM ──────────────────────────────────────────────────────────────
    typedef enum logic [3:0] {
        DL_IDLE, DL_RMSNORM1, DL_QKV, DL_ROPE,
        DL_KV_WRITE, DL_KV_READ, DL_MHA,
        DL_RESID1, DL_RMSNORM2, DL_FFN,
        DL_RESID2, DL_OUTPUT, DL_DONE
    } dl_state_t;
    dl_state_t dl_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dl_state<=DL_IDLE; done<=0;
            rn1_vin<=0; qkv_start<=0; rope_start<=0;
            kvc_start<=0; mha_start<=0; rn2_vin<=0; ffn_start<=0;
            for(int i=0;i<HIDDEN;i++) begin x_in_buf[i]<='0; x2[i]<='0; x_out[i]<='0; end
        end else begin
            done<=0;
            rn1_vin<=0; qkv_start<=0; rope_start<=0;
            kvc_start<=0; mha_start<=0; rn2_vin<=0; ffn_start<=0;
            case(dl_state)
                DL_IDLE: if(start) begin
                    for(int i=0;i<HIDDEN;i++) x_in_buf[i]<=x_in[i];
                    rn1_vin<=1; dl_state<=DL_RMSNORM1;
                end
                DL_RMSNORM1: if(rn1_vout) begin qkv_start<=1; dl_state<=DL_QKV; end
                DL_QKV:      if(qkv_done) begin rope_start<=1; dl_state<=DL_ROPE; end
                DL_ROPE:     if(rope_done) begin kvc_start<=1; dl_state<=DL_KV_WRITE; end
                DL_KV_WRITE: dl_state<=DL_KV_READ;
                DL_KV_READ:  if(kvc_done) begin mha_start<=1; dl_state<=DL_MHA; end
                DL_MHA:      if(mha_done) dl_state<=DL_RESID1;
                DL_RESID1: begin
                    for(int i=0;i<HIDDEN;i++) begin
                        automatic logic signed [8:0] s=
                            $signed(x_in_buf[i])+$signed(attn_out[i]);
                        x2[i]<=(s>127)?8'sd127:(s<-128)?-8'sd128:s[7:0];
                    end
                    rn2_vin<=1; dl_state<=DL_RMSNORM2;
                end
                DL_RMSNORM2: if(rn2_vout) begin ffn_start<=1; dl_state<=DL_FFN; end
                DL_FFN:      if(ffn_done) dl_state<=DL_RESID2;
                DL_RESID2: begin
                    for(int i=0;i<HIDDEN;i++) begin
                        automatic logic signed [8:0] s=
                            $signed(x2[i])+$signed(ffn_out[i]);
                        x_out[i]<=(s>127)?8'sd127:(s<-128)?-8'sd128:s[7:0];
                    end
                    dl_state<=DL_OUTPUT;
                end
                DL_OUTPUT: dl_state<=DL_DONE;
                DL_DONE:   begin done<=1; dl_state<=DL_IDLE; end
                default:   dl_state<=DL_IDLE;
            endcase
        end
    end

    assign sram_raddr = '0;

endmodule
