// =============================================================================
// dram_model.sv  —  AXI4 Slave BFM (DRAM 시뮬레이터) [UVM용]
//
// [역할]
//   DUT dma_engine의 AXI4 Master에 응답하는 슬레이브 BFM.
//   bkdoor(dram_backdoor_if)를 통해 UVM driver/monitor와 메모리 공유.
//
// [주의] interface 포트(bkdoor)를 사용하므로 VCS/Questasim 전용.
//        iverilog 시뮬레이션은 tb_sram_sim.sv의 inline DRAM BFM 사용.
//
// [Read FSM]
//   RD_IDLE → (ARVALID AND ARREADY) → RD_BUSY → R beat 스트리밍 → RD_IDLE
//   응답 레이턴시: 0사이클 (AR 수락 즉시 R 데이터 공급)
//
// [Write FSM]
//   WR_IDLE → (AWVALID AND AWREADY) → WR_DATA → W beat 수신 → WR_RESP → WR_IDLE
// =============================================================================
`default_nettype none

module dram_model #(
    parameter int AXI_DW = 64,
    parameter int ADDR_W = 32
)(
    input logic clk, rst_n,
    dram_backdoor_if bkdoor,   // 공유 메모리 인터페이스 (UVM 컴포넌트와 동일 인스턴스)
    input  logic [ADDR_W-1:0] s_araddr, input logic [7:0] s_arlen,
    input  logic [2:0] s_arsize, input logic [1:0] s_arburst,
    input  logic s_arvalid, output logic s_arready,
    output logic [AXI_DW-1:0] s_rdata, output logic [1:0] s_rresp,
    output logic s_rlast, s_rvalid, input logic s_rready,
    input  logic [ADDR_W-1:0] s_awaddr, input logic [7:0] s_awlen,
    input  logic [2:0] s_awsize, input logic [1:0] s_awburst,
    input  logic s_awvalid, output logic s_awready,
    input  logic [AXI_DW-1:0] s_wdata, input logic [(AXI_DW/8)-1:0] s_wstrb,
    input  logic s_wlast, s_wvalid, output logic s_wready,
    output logic [1:0] s_bresp, output logic s_bvalid, input logic s_bready
);
    typedef enum logic [1:0] { RD_IDLE=2'd0, RD_BUSY=2'd1 } rd_state_t;
    rd_state_t rd_state;
    logic [ADDR_W-1:0] rd_base;
    logic [7:0] rd_cnt, rd_total;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state<=RD_IDLE; s_arready<=1'b1; s_rvalid<=1'b0;
            s_rlast<=1'b0; s_rresp<=2'b00; rd_cnt<='0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_arready<=1'b1; s_rvalid<=1'b0;
                    if (s_arvalid && s_arready) begin
                        rd_base<=s_araddr; rd_total<=s_arlen;
                        rd_cnt<='0; s_arready<=1'b0; rd_state<=RD_BUSY;
                    end
                end
                RD_BUSY: begin
                    s_rvalid<=1'b1;
                    // bkdoor.read_qword: 64-bit little-endian 패킹 (byte0→bits[7:0])
                    s_rdata <=bkdoor.read_qword(int'(rd_base)+rd_cnt*8);
                    s_rlast <=(rd_cnt==rd_total);
                    s_rresp <=2'b00;
                    if (s_rvalid && s_rready) begin
                        if (rd_cnt==rd_total) begin
                            s_rvalid<=1'b0; s_rlast<=1'b0;
                            s_arready<=1'b1; rd_state<=RD_IDLE;
                        end else rd_cnt<=rd_cnt+1'b1;
                    end
                end
            endcase
        end
    end

    typedef enum logic [1:0] { WR_IDLE=2'd0, WR_DATA=2'd1, WR_RESP=2'd2 } wr_state_t;
    wr_state_t wr_state;
    logic [ADDR_W-1:0] wr_base;
    logic [7:0] wr_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state<=WR_IDLE; s_awready<=1'b1;
            s_wready<=1'b0; s_bvalid<=1'b0; s_bresp<=2'b00; wr_cnt<='0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_awready<=1'b1; s_wready<=1'b0; s_bvalid<=1'b0;
                    if (s_awvalid && s_awready) begin
                        wr_base<=s_awaddr; wr_cnt<='0;
                        s_awready<=1'b0; s_wready<=1'b1; wr_state<=WR_DATA;
                    end
                end
                WR_DATA: begin
                    if (s_wvalid && s_wready) begin
                        bkdoor.write_qword(int'(wr_base)+wr_cnt*8, s_wdata);
                        wr_cnt<=wr_cnt+1'b1;
                        if (s_wlast) begin
                            s_wready<=1'b0; s_bvalid<=1'b1;
                            s_bresp<=2'b00; wr_state<=WR_RESP;
                        end
                    end
                end
                WR_RESP: begin
                    if (s_bvalid && s_bready) begin
                        s_bvalid<=1'b0; s_awready<=1'b1; wr_state<=WR_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
`default_nettype wire
