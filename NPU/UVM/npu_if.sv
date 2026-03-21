// =============================================================================
// npu_if.sv  —  APB Slave + 상태 신호 인터페이스
//
// [역할]
//   DUT(npu_top_ws)의 APB 포트를 UVM 환경과 연결.
//   task apb_write/read: driver가 레지스터 설정에 사용.
//   wire apb_wr_active: monitor가 polling 없이 이벤트 기반 스누핑.
//   task wait_done: driver가 NPU 완료 대기에 사용.
//
// [APB 타이밍 (pready=1 고정)]
//   T0: psel=1, penable=0 (Setup 단계)
//   T1: penable=1 (Access 단계) → pready=1이므로 즉시 완료
//   T2: psel=0, penable=0 (Idle)
//   총 3 posedge 소요
// =============================================================================

interface npu_if (
    input logic clk,
    input logic rst_n
);
    logic [31:0] paddr, pwdata, prdata;
    logic        psel, penable, pwrite, pready;
    logic        npu_done, npu_busy;

    // APB Write: negedge에서 드라이브 → posedge에 DUT 샘플링 setup time 확보
    task automatic apb_write(input logic [31:0] addr, input logic [31:0] data);
        @(negedge clk);
        paddr=addr; psel=1'b1; pwrite=1'b1; pwdata=data; penable=1'b0;
        @(negedge clk);
        penable=1'b1;
        @(posedge clk);
        @(negedge clk);
        psel=1'b0; penable=1'b0; pwrite=1'b0;
    endtask

    // APB Read: Access 단계 posedge에서 prdata 캡처
    task automatic apb_read(input logic [31:0] addr, output logic [31:0] data);
        @(negedge clk);
        paddr=addr; psel=1'b1; pwrite=1'b0; penable=1'b0;
        @(negedge clk);
        penable=1'b1;
        @(posedge clk);
        data=prdata;
        @(negedge clk);
        psel=1'b0; penable=1'b0;
    endtask

    // done 대기: timeout 초과 시 $fatal → deadlock 방지
    task automatic wait_done(input int timeout = 100_000);
        int cnt = 0;
        @(posedge clk);
        while (!npu_done) begin
            @(posedge clk);
            if (++cnt > timeout)
                $fatal(1, "[npu_if] wait_done TIMEOUT (%0d cycles)", timeout);
        end
    endtask

    // APB 쓰기 완료 감지 wire: monitor가 이벤트 기반으로 트리거
    // psel AND penable AND pwrite AND pready = APB Access 단계 완료
    wire apb_wr_active = psel & penable &  pwrite & pready;
    wire apb_rd_active = psel & penable & ~pwrite & pready;
endinterface
