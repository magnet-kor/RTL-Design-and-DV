// =============================================================================
// accumulator.sv  —  Partial Sum Accumulator
//
// [역할]
//   systolic_array_ws의 c_out(SA_SIZE개 INT32 값)을 받아 래치.
//   acc_clr=0이면 이전 값에 누적 → 다중 타일(K > SA_SIZE) 지원 가능.
//
// [단일 타일 동작 (K=SA_SIZE=8)]
//   ACC_LATCH 상태에서 acc_clr=1, acc_en=1 동시 어서트
//   → acc_out = c_in (초기화 후 래치), acc_valid=1 1사이클 펄스
//
// [다중 타일 동작 (K=16 예시)]
//   타일 0: acc_clr=1 → acc_out = c_out_tile0
//   타일 1: acc_clr=0 → acc_out = acc_out + c_out_tile1
//   → K개 열을 SA_SIZE 단위 타일링으로 처리
//
// [타이밍]
//   acc_en 어서트 → 다음 posedge에 acc_out 유효 + acc_valid=1 (1사이클)
// =============================================================================
`default_nettype none

module accumulator #(
    parameter int SA_SIZE = 8,
    parameter int ACC_W   = 32
)(
    input  wire                                        clk,
    input  wire                                        rst_n,
    input  wire                                        acc_en,    // 래치 트리거
    input  wire                                        acc_clr,   // 1=초기화, 0=누적
    input  wire signed [ACC_W-1:0]  c_in  [0:SA_SIZE-1],
    output reg  signed [ACC_W-1:0]  acc_out [0:SA_SIZE-1],
    output reg                       acc_valid
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int j = 0; j < SA_SIZE; j++) acc_out[j] <= '0;
            acc_valid <= 1'b0;
        end else begin
            acc_valid <= 1'b0;   // 매 사이클 자동 해제 (1사이클 펄스)
            if (acc_en) begin
                for (int j = 0; j < SA_SIZE; j++) begin
                    if (acc_clr)
                        acc_out[j] <= c_in[j];               // 초기화 + 래치
                    else
                        acc_out[j] <= acc_out[j] + c_in[j];  // 누적
                end
                acc_valid <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
