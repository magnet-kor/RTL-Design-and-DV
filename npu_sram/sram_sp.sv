// =============================================================================
// sram_sp.sv  —  Generic Single-Port Synchronous SRAM (Behavioral Model)
//
// [추가 목적]
//   control_unit의 weight_buf 레지스터 배열(512-bit FF)을 SRAM으로 교체.
//   RTL 시뮬레이션은 behavioral 모델로 검증, 구현 시 SRAM 컴파일러 출력으로 대체.
//
// [인터페이스 설계 원칙 — Samsung/TSMC SRAM compiler 관례]
//   cs_n: chip select, active-low  (선택된 경우에만 동작)
//   we_n: write enable, active-low (0이면 write, 1이면 read)
//   동기 쓰기 / 비동기 읽기 구조 선택 이유:
//     - 동기 쓰기: posedge에 캡처 → control_unit nonblocking 할당과 타이밍 동일
//     - 비동기 읽기: LOAD_W_SA에서 addr 변경 즉시 wt_col에 반영 → 추가 사이클 불필요
//       (registered read로 변경하면 LOAD_W_SA 타이밍을 1사이클 앞당겨야 함)
//
// [NPU 내 용도]
//   DEPTH=8, WIDTH=64: 8 entries × 64-bit = 64 bytes = 8×8 INT8 weight 행렬
//   AXI4 burst beat(64-bit) 1회 = SRAM entry 1개 → 직결 가능 (변환 없음)
//
// [파라미터]
//   DEPTH  : word 수 (2의 거듭제곱 필수)
//   WIDTH  : word당 bit 수
//   ADDR_W : 주소 비트 수 ($clog2(DEPTH), 인스턴스에서 명시 권장)
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module sram_sp #(
    parameter int DEPTH  = 64,
    parameter int WIDTH  = 8,
    parameter int ADDR_W = $clog2(DEPTH)
)(
    input  wire              clk,
    input  wire              cs_n,         // chip select, active-low
    input  wire              we_n,         // write enable, active-low
    input  wire [ADDR_W-1:0] addr,
    input  wire [WIDTH-1:0]  wdata,
    output wire [WIDTH-1:0]  rdata         // 비동기 읽기
);
    // 내부 메모리: packed array (연속 할당 → associative 대비 ~3× 빠름)
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // 시뮬레이션 초기화 (synthesis translate_off로 합성 제외)
    // synthesis translate_off
    initial for (int i = 0; i < DEPTH; i++) mem[i] = '0;
    // synthesis translate_on

    // 동기 쓰기: cs_n=0(선택) AND we_n=0(쓰기 허용)일 때 posedge에 캡처
    always @(posedge clk)
        if (!cs_n && !we_n) mem[addr] <= wdata;

    // 비동기 읽기: cs_n=0 AND we_n=1일 때 즉시 유효
    // cs_n=1: High-Z 출력 (멀티 소스 버스 환경 대비, 전력 절약)
    assign rdata = (!cs_n && we_n) ? mem[addr] : {WIDTH{1'bz}};

endmodule
`default_nettype wire
