// =============================================================================
// post_proc.sv  —  Post Processing (INT32 → INT8 양자화)
//
// [처리 순서 — 1사이클 파이프라인]
//   Step1. ReLU:  x = max(0, acc_in)     [음수 제거]
//   Step2. Scale: x = x >>> scale        [산술 우시프트, 부호 보존]
//   Step3. Clamp: x = clip(x, -128, 127) [INT8 범위 강제]
//   Step4. 출력:  pp_out[7:0]            [INT8 2의 보수]
//
// [scale 값 선택 근거]
//   acc_out_max = 127×127×SA_SIZE = 129,032 ≈ 2^17
//   scale=7:  129,032 >> 7 = 1,008 → 클램프 발동 (포화 케이스 검증용)
//   scale=10: 129,032 >> 10 = 126  → INT8 범위 내 안전
//   실제 추론: 레이어별 quantization parameter로 cfg_scale 조정
//
// [타이밍]
//   pp_en 어서트 사이클 다음 posedge에서 pp_out, pp_valid 유효
// =============================================================================
`default_nettype none

module post_proc #(
    parameter int SA_SIZE = 8,
    parameter int ACC_W   = 32,
    parameter int DATA_W  = 8
)(
    input  wire                                        clk,
    input  wire                                        rst_n,
    input  wire                                        pp_en,
    input  wire [4:0]                                  scale,
    input  wire signed [ACC_W-1:0]  acc_in  [0:SA_SIZE-1],
    output reg  signed [DATA_W-1:0] pp_out  [0:SA_SIZE-1],
    output reg                       pp_valid
);
    // 조합 논리: ReLU + 산술 우시프트 (클럭 불필요)
    wire signed [ACC_W-1:0] relu_out [0:SA_SIZE-1];
    wire signed [ACC_W-1:0] scaled   [0:SA_SIZE-1];

    genvar j;
    generate
        for (j = 0; j < SA_SIZE; j++) begin : gen_pp
            // ReLU: 음수를 0으로 클리핑
            assign relu_out[j] = (acc_in[j] < 0) ? '0 : acc_in[j];
            // 산술 우시프트: $signed()로 선언된 wire에서 >>> 는 산술 시프트 보장
            assign scaled[j]   = relu_out[j] >>> scale;
        end
    endgenerate

    // 등록 단계: 클램프 + 출력 래치
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int j = 0; j < SA_SIZE; j++) pp_out[j] <= '0;
            pp_valid <= 1'b0;
        end else begin
            pp_valid <= 1'b0;
            if (pp_en) begin
                for (int j = 0; j < SA_SIZE; j++) begin
                    // 클램프: INT8 범위 [-128, 127]
                    if      ($signed(scaled[j]) >  32'sd127) pp_out[j] <=  8'sd127;
                    else if ($signed(scaled[j]) < -32'sd128) pp_out[j] <= -8'sd128;
                    else    pp_out[j] <= scaled[j][DATA_W-1:0];
                end
                pp_valid <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
