// =============================================================================
// host_interface.sv  —  APB Slave Host Interface
//
// [APB 선택 이유]
//   2-cycle 트랜잭션(Setup→Enable) — 단순 레지스터 설정에 충분.
//   고속 데이터 이동은 DMA가 AXI4로 직접 처리 → CPU는 설정만 담당.
//
// [레지스터 맵 (32-bit, byte 주소, paddr[5:2] = 워드 인덱스)]
//   0x00 (sel=0): REG_WGT_ADDR  — Weight DRAM 시작 주소
//   0x04 (sel=1): REG_ACT_ADDR  — Activation DRAM 시작 주소
//   0x08 (sel=2): REG_OUT_ADDR  — Output DRAM 시작 주소
//   0x0C (sel=3): REG_SCALE     — Post-proc 우시프트 양 [4:0]
//   0x10 (sel=4): REG_CTRL      — [0]=start (self-clearing 1사이클 펄스)
//   0x14 (sel=5): REG_STATUS    — [0]=done (RO), [1]=busy (RO)
//
// [start self-clearing]
//   start <= 1'b0 매 사이클 실행 → REG_CTRL[0]=1 쓰기 시 딱 1사이클만 high
//   FSM이 start 펄스를 감지해 IDLE → LOAD_W_DMA 전이
// =============================================================================
`default_nettype none

module host_interface #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    // APB Slave
    input  wire [ADDR_W-1:0] paddr,
    input  wire              psel,
    input  wire              penable,
    input  wire              pwrite,
    input  wire [DATA_W-1:0] pwdata,
    output reg  [DATA_W-1:0] prdata,
    output wire              pready,     // 항상 1 (no wait state)
    // 설정 출력
    output reg  [31:0]       cfg_wgt_addr,
    output reg  [31:0]       cfg_act_addr,
    output reg  [31:0]       cfg_out_addr,
    output reg  [4:0]        cfg_scale,
    output reg               start,
    // 상태 입력
    input  wire              done,
    input  wire              busy
);
    assign pready = 1'b1;

    wire apb_wr  = psel & penable &  pwrite;
    wire apb_rd  = psel & penable & ~pwrite;
    wire [3:0] reg_sel = paddr[5:2];

    // 쓰기 레지스터 (동기 리셋)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_wgt_addr <= '0; cfg_act_addr <= '0;
            cfg_out_addr <= '0; cfg_scale <= '0; start <= 1'b0;
        end else begin
            start <= 1'b0;   // self-clearing: 매 사이클 0으로 초기화
            if (apb_wr) begin
                case (reg_sel)
                    4'h0: cfg_wgt_addr <= pwdata;
                    4'h1: cfg_act_addr <= pwdata;
                    4'h2: cfg_out_addr <= pwdata;
                    4'h3: cfg_scale    <= pwdata[4:0];
                    4'h4: if (pwdata[0]) start <= 1'b1;
                    default: ;
                endcase
            end
        end
    end

    // 읽기 레지스터 (동기)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) prdata <= '0;
        else if (apb_rd) begin
            case (reg_sel)
                4'h0: prdata <= cfg_wgt_addr;
                4'h1: prdata <= cfg_act_addr;
                4'h2: prdata <= cfg_out_addr;
                4'h3: prdata <= {27'b0, cfg_scale};
                4'h4: prdata <= 32'b0;
                4'h5: prdata <= {30'b0, busy, done};
                default: prdata <= '0;
            endcase
        end
    end
endmodule
`default_nettype wire
