// =============================================================================
// pe_ws.sv  —  Weight Stationary Processing Element
//
// WS dataflow의 최소 연산 단위. 8×8 배열로 연결되어 systolic_array_ws를 구성.
//
// [동작 원리]
//   wload=1 : wt_in → weight_reg 래치, wt_out으로 하단 PE 전달
//             → SA_SIZE 사이클 역순 로딩으로 2D 배열 전체에 W[r][c] 정착
//   pe_en=1 : act_in × weight_reg → ps_in + product → ps_out (수직 누적)
//             act_in → act_out으로 우측 PE 전달 (수평 파이프라인)
//
// [wt_out 단일 레지스터 핵심]
//   wt_out <= wt_in (단일 FF): PE[r]까지 r사이클 전파
//   wt_out <= weight_reg (이중 FF, 금지): PE[r]까지 2r+1사이클 → SA_SIZE 사이클 로딩 불가
//   예: SA_SIZE=8, r=7이면 단일=7사이클 OK, 이중=15사이클 → 로딩 실패
//
// [비트폭 근거]
//   DATA_W=8 → INT8 입출력
//   ACC_W=32 → INT32 누적 (max = 127×127×8 = 129,032 ≪ 2^31, 오버플로 없음)
// =============================================================================
`default_nettype none

module pe_ws #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,    // 비동기 active-low 리셋

    input  wire                     pe_en,    // compute 활성화 + act 수평 이동
    input  wire                     wload,    // weight 로딩 (pe_en과 동시 금지)

    // Activation — 수평 (좌 → 우)
    input  wire signed [DATA_W-1:0] act_in,
    output reg  signed [DATA_W-1:0] act_out,

    // Weight — 수직 (위 → 아래, wload 구간만)
    input  wire signed [DATA_W-1:0] wt_in,
    output reg  signed [DATA_W-1:0] wt_out,

    // Partial Sum — 수직 누적 (위 → 아래)
    input  wire signed [ACC_W-1:0]  ps_in,   // 행 0: 외부에서 0 공급
    output reg  signed [ACC_W-1:0]  ps_out
);

    // weight_reg: WS dataflow의 핵심 — wload 중에만 갱신, pe_en 중에는 동결
    // 이유: weight가 고정된 채로 activation이 흘러야 weight-stationary
    reg  signed [DATA_W-1:0]   weight_reg;

    // product: 16-bit (8×8 곱셈 결과), ACC_W로 부호 확장 후 ps_in에 가산
    wire signed [DATA_W*2-1:0] product = $signed(act_in) * $signed(weight_reg);

    // weight_reg: wload 전용 게이팅 (pe_en=1이어도 동결 → WS 보장)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)     weight_reg <= '0;
        else if (wload) weight_reg <= wt_in;
    end

    // wt_out: 단일 레지스터 직결 — PE[r]까지 r사이클 지연으로 수직 skew 전파
    // wload=0이면 갱신하지 않아도 됨 (pe_en 중에는 wt_out이 don't care)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)     wt_out <= '0;
        else if (wload) wt_out <= wt_in;
    end

    // act_out: 수평 파이프라인 — 같은 activation이 열을 따라 좌→우로 흐름
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      act_out <= '0;
        else if (pe_en)  act_out <= act_in;
    end

    // ps_out: 부분합 수직 누적
    // 부호 확장: product[15:0] → 32-bit 산술 확장 후 ps_in과 가산
    // {{(ACC_W-DATA_W*2){product[MSB]}}, product}: MSB 복제로 부호 보존
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ps_out <= '0;
        else if (pe_en)
            ps_out <= ps_in
                    + $signed({{(ACC_W-DATA_W*2){product[DATA_W*2-1]}}, product});
    end

endmodule
`default_nettype wire
