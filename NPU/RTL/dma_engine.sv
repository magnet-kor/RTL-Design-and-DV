// =============================================================================
// dma_engine.sv  —  AXI4 Master DMA Engine
//
// [지원 트랜잭션]
//   Read:  AR 채널 → R 채널 beat 스트리밍 → rd_vld/rd_data/rd_beat
//   Write: AW 채널 → W 채널 beat 전송 → B 채널 응답 확인
//
// [AXI4 파라미터]
//   ARSIZE=3'b011: 8 bytes/beat (64-bit 버스 전체 사용)
//   ARBURST=INCR:  순차 주소 증가 (NPU는 랜덤 접근 없음)
//   ARLEN=beats-1: beats-1 인코딩 (Weight: ARLEN=7=Burst-8, Act/Out: ARLEN=0=Burst-1)
//
// [버스트 효율]
//   Weight(64bytes): 1(AR) + 8(data) = 9사이클, 효율 8/9 = 88.9%
//   Act/Out(8bytes): 1(AR) + 1(data) = 2사이클, 효율 1/2 = 50% (크기가 작아 허용)
//
// [FSM 전이]
//   Read:  IDLE → AR_SEND → R_RECV → DONE → IDLE
//   Write: IDLE → AW_SEND → W_SEND → B_RECV → DONE → IDLE
// =============================================================================
`default_nettype none

module dma_engine #(
    parameter int ADDR_W = 32,
    parameter int AXI_DW = 64
)(
    input  wire              clk, rst_n,
    // 제어 인터페이스 (Control Unit)
    input  wire              dma_req,       // 1=전송 시작
    input  wire              dma_wr,        // 0=read, 1=write
    input  wire [ADDR_W-1:0] dma_addr,      // DRAM 시작 주소
    input  wire [7:0]        dma_beats,     // beat 수 (1-based)
    // Read 스트리밍 출력 → Control Unit
    output logic             rd_vld,
    output logic [AXI_DW-1:0] rd_data,
    output logic [7:0]       rd_beat,       // beat 인덱스 (0~beats-1)
    // Write 스트리밍 입력 ← Control Unit
    input  wire              wr_vld,
    input  wire [AXI_DW-1:0] wr_data,
    output logic             wr_rdy,
    output logic             dma_done,      // 완료 1사이클 펄스
    // AXI4 AR
    output logic [ADDR_W-1:0] m_araddr,
    output logic [7:0]        m_arlen,
    output logic [2:0]        m_arsize,
    output logic [1:0]        m_arburst,
    output logic              m_arvalid,
    input  wire               m_arready,
    // AXI4 R
    input  wire  [AXI_DW-1:0] m_rdata,
    input  wire  [1:0]         m_rresp,
    input  wire                m_rlast,
    input  wire                m_rvalid,
    output logic               m_rready,
    // AXI4 AW
    output logic [ADDR_W-1:0] m_awaddr,
    output logic [7:0]        m_awlen,
    output logic [2:0]        m_awsize,
    output logic [1:0]        m_awburst,
    output logic              m_awvalid,
    input  wire               m_awready,
    // AXI4 W
    output logic [AXI_DW-1:0] m_wdata,
    output logic [(AXI_DW/8)-1:0] m_wstrb,
    output logic              m_wlast,
    output logic              m_wvalid,
    input  wire               m_wready,
    // AXI4 B
    input  wire  [1:0]         m_bresp,
    input  wire                m_bvalid,
    output logic               m_bready
);
    localparam [2:0] ARSIZE_8B  = 3'b011;
    localparam [1:0] BURST_INCR = 2'b01;

    typedef enum logic [2:0] {
        IDLE=3'd0, AR_SEND=3'd1, R_RECV=3'd2,
        AW_SEND=3'd3, W_SEND=3'd4, B_RECV=3'd5, DONE=3'd6
    } state_t;

    state_t  state;
    logic [7:0] beat_cnt, total_beats;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; beat_cnt <= '0; total_beats <= '0; dma_done <= 1'b0;
        end else begin
            dma_done <= 1'b0;
            case (state)
                IDLE:
                    if (dma_req) begin
                        total_beats <= dma_beats;
                        beat_cnt    <= '0;
                        // dma_wr=0이면 읽기(AR_SEND), 1이면 쓰기(AW_SEND)
                        state <= dma_wr ? AW_SEND : AR_SEND;
                    end
                // ── Read Path ──
                // AR_SEND: ARVALID=1 어서트, ARREADY=1 감지 시 주소 수락
                AR_SEND: if (m_arready) state <= R_RECV;
                // R_RECV: RVALID AND RREADY = 1 beat transfer 완료
                //         RLAST=1이면 마지막 beat → DONE
                R_RECV:
                    if (m_rvalid && m_rready) begin
                        if (m_rlast) state <= DONE;
                        else         beat_cnt <= beat_cnt + 1'b1;
                    end
                // ── Write Path ──
                AW_SEND: if (m_awready) begin state <= W_SEND; beat_cnt <= '0; end
                // W_SEND: wr_vld AND WREADY = 1 beat 전달
                //         beat_cnt == total_beats-1이면 마지막 → B_RECV
                W_SEND:
                    if (wr_vld && m_wready) begin
                        if (beat_cnt == total_beats - 1) state <= B_RECV;
                        else beat_cnt <= beat_cnt + 1'b1;
                    end
                B_RECV: if (m_bvalid) state <= DONE;
                DONE:   begin dma_done <= 1'b1; state <= IDLE; end
                default: state <= IDLE;
            endcase
        end
    end

    // AR 채널: ARLEN=total_beats-1 (AXI4 인코딩: beats-1)
    assign m_araddr  = dma_addr;
    assign m_arlen   = total_beats - 8'd1;
    assign m_arsize  = ARSIZE_8B;
    assign m_arburst = BURST_INCR;
    assign m_arvalid = (state == AR_SEND);
    assign m_rready  = (state == R_RECV);
    // rd_vld: R_RECV 상태에서 RVALID=1일 때만 Control Unit에 유효 데이터 알림
    assign rd_vld    = (state == R_RECV) && m_rvalid;
    assign rd_data   = m_rdata;
    assign rd_beat   = beat_cnt;

    // AW/W/B 채널
    assign m_awaddr  = dma_addr;
    assign m_awlen   = total_beats - 8'd1;
    assign m_awsize  = ARSIZE_8B;
    assign m_awburst = BURST_INCR;
    assign m_awvalid = (state == AW_SEND);
    assign m_wdata   = wr_data;
    assign m_wstrb   = {(AXI_DW/8){1'b1}};  // 모든 바이트 유효
    // WLAST: 마지막 beat임을 슬레이브에 알림
    assign m_wlast   = (state == W_SEND) && (beat_cnt == total_beats - 1);
    assign m_wvalid  = (state == W_SEND) && wr_vld;
    assign wr_rdy    = (state == W_SEND) && m_wready;
    assign m_bready  = (state == B_RECV);
endmodule
`default_nettype wire
