// =============================================================================
// npu_top_ws.sv  —  Weight Stationary NPU Top Level
//
// [모듈 구성]
//   host_interface    : CPU ↔ APB, 설정 레지스터 6개
//   control_unit      : 메인 FSM, [SRAM] weight buffer, act/out 레지스터 버퍼
//   dma_engine        : AXI4 Master (DRAM 읽기/쓰기)
//   systolic_array_ws : 8×8 WS 배열 (64개 PE)
//   accumulator       : PS 수집 및 다중 타일 누적 지원
//   post_proc         : INT32 → INT8 양자화 (ReLU + Scale + Clamp)
//
// [SRAM 포함 경로]
//   npu_top_ws → control_unit → u_sram_wgt (sram_sp)
//
// [외부 포트]
//   APB slave: CPU가 NPU 파라미터 설정 및 start/done 폴링
//   AXI4 master: DMA가 DRAM에서 weight/activation 읽고 output 기록
//
// [데이터 흐름]
//   CPU → APB → host_interface → start → control_unit
//   control_unit → DMA → DRAM (weight read) → SRAM u_sram_wgt
//   SRAM → wt_col → systolic_array_ws (LOAD_W_SA, 역순 8사이클)
//   control_unit → DMA → DRAM (act read) → act_buf
//   act_buf → raw_act → systolic_array_ws (COMPUTE 1사이클)
//   c_out → accumulator → post_proc → out_buf
//   out_buf → DMA → DRAM (output write)
// =============================================================================
`default_nettype none

module npu_top_ws #(
    parameter int SA_SIZE   = 8,
    parameter int DATA_W    = 8,
    parameter int ACC_W     = 32,
    parameter int APB_AW    = 32,
    parameter int APB_DW    = 32,
    parameter int AXI_ADDRW = 32,
    parameter int AXI_DW    = 64
)(
    input  wire              clk,
    input  wire              rst_n,
    // APB Slave (CPU)
    input  wire [APB_AW-1:0] paddr,
    input  wire              psel, penable, pwrite,
    input  wire [APB_DW-1:0] pwdata,
    output wire [APB_DW-1:0] prdata,
    output wire              pready,
    // AXI4 Master (DRAM)
    output wire [AXI_ADDRW-1:0] m_araddr,
    output wire [7:0]  m_arlen,  output wire [2:0] m_arsize,
    output wire [1:0]  m_arburst, output wire m_arvalid,
    input  wire        m_arready,
    input  wire [AXI_DW-1:0] m_rdata, input wire [1:0] m_rresp,
    input  wire m_rlast, m_rvalid, output wire m_rready,
    output wire [AXI_ADDRW-1:0] m_awaddr,
    output wire [7:0]  m_awlen,  output wire [2:0] m_awsize,
    output wire [1:0]  m_awburst, output wire m_awvalid,
    input  wire        m_awready,
    output wire [AXI_DW-1:0]    m_wdata,
    output wire [(AXI_DW/8)-1:0] m_wstrb,
    output wire m_wlast, m_wvalid, input wire m_wready,
    input  wire [1:0]  m_bresp,  input wire  m_bvalid,
    output wire        m_bready
);
    // 내부 연결 신호
    wire [31:0] cfg_wgt_addr, cfg_act_addr, cfg_out_addr;
    wire [4:0]  cfg_scale;
    wire        start, npu_done, npu_busy;
    wire        dma_req, dma_wr_ctrl;
    wire [31:0] dma_addr;
    wire [7:0]  dma_beats;
    wire        dma_done, dma_rd_vld;
    wire [63:0] dma_rd_data;
    wire [7:0]  dma_rd_beat;
    wire        dma_wr_vld;
    wire [63:0] dma_wr_data;
    wire        dma_wr_rdy;
    wire signed [DATA_W-1:0] wt_col  [0:SA_SIZE-1];
    wire                      wload;
    wire signed [DATA_W-1:0] raw_act [0:SA_SIZE-1];
    wire                      pe_en;
    wire signed [ACC_W-1:0]  c_out    [0:SA_SIZE-1];
    wire        acc_en, acc_clr;
    wire signed [ACC_W-1:0]  acc_out  [0:SA_SIZE-1];
    wire                      acc_valid;
    wire        pp_en;
    wire [4:0]  pp_scale;
    wire signed [DATA_W-1:0] pp_out   [0:SA_SIZE-1];
    wire                      pp_valid;

    host_interface #(.ADDR_W(APB_AW),.DATA_W(APB_DW)) u_hif (
        .clk(clk),.rst_n(rst_n),.paddr(paddr),.psel(psel),
        .penable(penable),.pwrite(pwrite),.pwdata(pwdata),
        .prdata(prdata),.pready(pready),
        .cfg_wgt_addr(cfg_wgt_addr),.cfg_act_addr(cfg_act_addr),
        .cfg_out_addr(cfg_out_addr),.cfg_scale(cfg_scale),
        .start(start),.done(npu_done),.busy(npu_busy)
    );

    // control_unit 내부에 sram_sp u_sram_wgt 포함
    control_unit #(.SA_SIZE(SA_SIZE),.DATA_W(DATA_W),.ACC_W(ACC_W),.ADDR_W(AXI_ADDRW)) u_ctrl (
        .clk(clk),.rst_n(rst_n),
        .cfg_wgt_addr(cfg_wgt_addr),.cfg_act_addr(cfg_act_addr),
        .cfg_out_addr(cfg_out_addr),.cfg_scale(cfg_scale),.start(start),
        .dma_req(dma_req),.dma_wr(dma_wr_ctrl),.dma_addr(dma_addr),
        .dma_beats(dma_beats),.dma_done(dma_done),
        .dma_rd_vld(dma_rd_vld),.dma_rd_data(dma_rd_data),.dma_rd_beat(dma_rd_beat),
        .dma_wr_vld(dma_wr_vld),.dma_wr_data(dma_wr_data),.dma_wr_rdy(dma_wr_rdy),
        .wt_col(wt_col),.wload(wload),.raw_act(raw_act),.pe_en(pe_en),
        .acc_en(acc_en),.acc_clr(acc_clr),
        .pp_en(pp_en),.pp_scale(pp_scale),
        .pp_out(pp_out),.pp_valid(pp_valid),
        .done(npu_done),.busy(npu_busy)
    );

    dma_engine #(.ADDR_W(AXI_ADDRW),.AXI_DW(AXI_DW)) u_dma (
        .clk(clk),.rst_n(rst_n),
        .dma_req(dma_req),.dma_wr(dma_wr_ctrl),.dma_addr(dma_addr),
        .dma_beats(dma_beats),.rd_vld(dma_rd_vld),.rd_data(dma_rd_data),
        .rd_beat(dma_rd_beat),.wr_vld(dma_wr_vld),.wr_data(dma_wr_data),
        .wr_rdy(dma_wr_rdy),.dma_done(dma_done),
        .m_araddr(m_araddr),.m_arlen(m_arlen),.m_arsize(m_arsize),
        .m_arburst(m_arburst),.m_arvalid(m_arvalid),.m_arready(m_arready),
        .m_rdata(m_rdata),.m_rresp(m_rresp),.m_rlast(m_rlast),
        .m_rvalid(m_rvalid),.m_rready(m_rready),
        .m_awaddr(m_awaddr),.m_awlen(m_awlen),.m_awsize(m_awsize),
        .m_awburst(m_awburst),.m_awvalid(m_awvalid),.m_awready(m_awready),
        .m_wdata(m_wdata),.m_wstrb(m_wstrb),.m_wlast(m_wlast),
        .m_wvalid(m_wvalid),.m_wready(m_wready),
        .m_bresp(m_bresp),.m_bvalid(m_bvalid),.m_bready(m_bready)
    );

    systolic_array_ws #(.SA_SIZE(SA_SIZE),.DATA_W(DATA_W),.ACC_W(ACC_W)) u_sa (
        .clk(clk),.rst_n(rst_n),.pe_en(pe_en),.wload(wload),
        .wt_col(wt_col),.raw_act(raw_act),.c_out(c_out)
    );

    accumulator #(.SA_SIZE(SA_SIZE),.ACC_W(ACC_W)) u_acc (
        .clk(clk),.rst_n(rst_n),.acc_en(acc_en),.acc_clr(acc_clr),
        .c_in(c_out),.acc_out(acc_out),.acc_valid(acc_valid)
    );

    post_proc #(.SA_SIZE(SA_SIZE),.ACC_W(ACC_W),.DATA_W(DATA_W)) u_pp (
        .clk(clk),.rst_n(rst_n),.pp_en(pp_en),.scale(pp_scale),
        .acc_in(acc_out),.pp_out(pp_out),.pp_valid(pp_valid)
    );
endmodule
`default_nettype wire
