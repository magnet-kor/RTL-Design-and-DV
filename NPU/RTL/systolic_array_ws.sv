// =============================================================================
// systolic_array_ws.sv  —  NxN Weight Stationary Systolic Array
//
// [구성 3단계]
//   1. Activation Skew SR:
//      행 i → i사이클 지연. 이유: 행렬 곱셈에서 A[i][k]와 W[i][k]가
//      같은 사이클에 만나야 하므로 대각선 방향으로 데이터 흐름 정렬.
//      fill latency = SA_SIZE-1 = 7사이클 (첫 주입→마지막 행 도착)
//
//   2. PE 2D 배열:
//      Activation 수평 이동, PS 수직 누적.
//      c_out[j] 유효 시각: T = SA_SIZE + j (열 j의 PS 마지막 행 도달 시점)
//
//   3. 출력 정렬 SR:
//      열 j에 (SA_SIZE-1-j)사이클 추가 지연 → T=2*SA_SIZE-1에 전체 동시 유효
//      이 정렬이 없으면 accumulator가 각 열마다 다른 타이밍에 샘플해야 해서 복잡도 ↑
// =============================================================================
`default_nettype none

module systolic_array_ws #(
    parameter int SA_SIZE = 8,
    parameter int DATA_W  = 8,
    parameter int ACC_W   = 32
)(
    input  wire                                        clk,
    input  wire                                        rst_n,
    input  wire                                        pe_en,
    input  wire                                        wload,
    input  wire signed [DATA_W-1:0]  wt_col  [0:SA_SIZE-1],
    input  wire signed [DATA_W-1:0]  raw_act [0:SA_SIZE-1],
    output wire signed [ACC_W-1:0]   c_out   [0:SA_SIZE-1]
);

    // -----------------------------------------------------------------------
    // 1. Activation Skew SR: 행 i → i사이클 지연
    //    행 0: 지연 0 (직결), 행 i: FF i개 체인
    //    pe_en=1일 때만 이동 (pe_en=0이면 skew 레지스터 동결)
    // -----------------------------------------------------------------------
    wire signed [DATA_W-1:0] skewed_act [0:SA_SIZE-1];
    reg  signed [DATA_W-1:0] sc_act [0:SA_SIZE-1][0:SA_SIZE-2];

    genvar i, d;
    generate
        for (i = 0; i < SA_SIZE; i++) begin : gen_act_skew
            if (i == 0) begin : skew_0
                assign skewed_act[0] = raw_act[0];  // 행 0: 지연 없이 직결
            end else begin : skew_n
                // 첫 번째 FF: raw_act[i]를 1사이클 지연
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n)      sc_act[i][0] <= '0;
                    else if (pe_en)  sc_act[i][0] <= raw_act[i];
                end
                // 나머지 FF 체인: i-1개 추가 지연 (총 i사이클)
                for (d = 1; d < i; d++) begin : gen_chain
                    always @(posedge clk or negedge rst_n) begin
                        if (!rst_n)      sc_act[i][d] <= '0;
                        else if (pe_en)  sc_act[i][d] <= sc_act[i][d-1];
                    end
                end
                assign skewed_act[i] = sc_act[i][i-1];  // 마지막 FF 출력
            end
        end
    endgenerate

    // -----------------------------------------------------------------------
    // 2. PE 간 연결 Wire (수평 act, 수직 weight/PS)
    // -----------------------------------------------------------------------
    wire signed [DATA_W-1:0] act_h [0:SA_SIZE-1][0:SA_SIZE-1];
    wire signed [DATA_W-1:0] wt_v  [0:SA_SIZE-1][0:SA_SIZE-1];
    wire signed [ACC_W-1:0]  ps_v  [0:SA_SIZE-1][0:SA_SIZE-1];

    // -----------------------------------------------------------------------
    // 3. PE 2D 배열 인스턴스
    //    경계 조건: 첫 열(c=0)은 skewed_act, 첫 행(r=0)은 wt_col/PS=0 공급
    // -----------------------------------------------------------------------
    genvar r, c;
    generate
        for (r = 0; r < SA_SIZE; r++) begin : gen_row
            for (c = 0; c < SA_SIZE; c++) begin : gen_col
                pe_ws #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_pe (
                    .clk    (clk),
                    .rst_n  (rst_n),
                    .pe_en  (pe_en),
                    .wload  (wload),
                    .act_in (c == 0 ? skewed_act[r] : act_h[r][c-1]),
                    .act_out(act_h[r][c]),
                    .wt_in  (r == 0 ? wt_col[c]      : wt_v[r-1][c]),
                    .wt_out (wt_v[r][c]),
                    .ps_in  (r == 0 ? {ACC_W{1'b0}}  : ps_v[r-1][c]),
                    .ps_out (ps_v[r][c])
                );
            end
        end
    endgenerate

    // -----------------------------------------------------------------------
    // 4. 배열 하단 PS: ps_bot[j] 유효 시각 T = SA_SIZE + j
    // -----------------------------------------------------------------------
    wire signed [ACC_W-1:0] ps_bot [0:SA_SIZE-1];
    genvar jb;
    generate
        for (jb = 0; jb < SA_SIZE; jb++) begin : gen_bot
            assign ps_bot[jb] = ps_v[SA_SIZE-1][jb];
        end
    endgenerate

    // -----------------------------------------------------------------------
    // 5. 출력 정렬 SR: 열 j에 (SA_SIZE-1-j)사이클 지연 추가
    //    j=SA_SIZE-1(마지막 열): 지연 0, 직결
    //    j=0(첫 열): 지연 SA_SIZE-1 = 7사이클
    //    결과: 전체 c_out[0..7]이 T=2*SA_SIZE-1에 동시 유효
    // -----------------------------------------------------------------------
    reg  signed [ACC_W-1:0] out_sr [0:SA_SIZE-1][0:SA_SIZE-2];

    genvar j, dd;
    generate
        for (j = 0; j < SA_SIZE; j++) begin : gen_out
            if (j == SA_SIZE-1) begin : out_direct
                assign c_out[j] = ps_bot[j];     // 마지막 열: 직결
            end else begin : out_delayed
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) out_sr[j][0] <= '0;
                    else        out_sr[j][0] <= ps_bot[j];
                end
                for (dd = 1; dd <= SA_SIZE-2-j; dd++) begin : out_chain
                    always @(posedge clk or negedge rst_n) begin
                        if (!rst_n) out_sr[j][dd] <= '0;
                        else        out_sr[j][dd] <= out_sr[j][dd-1];
                    end
                end
                assign c_out[j] = out_sr[j][SA_SIZE-2-j];
            end
        end
    endgenerate

endmodule
`default_nettype wire
