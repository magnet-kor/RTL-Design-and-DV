// =============================================================================
// tb_sram_sim.sv  —  iverilog 호환 시뮬레이션 테스트벤치
//
// [목적]
//   UVM/VCS 없이 iverilog -g2012로 SRAM 통합 검증.
//   dram_backdoor_if 인터페이스 포트 대신 내부 메모리 배열을 직접 사용.
//
// [TC1] sram_sp 단독 동작 검증
//   쓰기: addr 0~7에 패턴 데이터 (각 byte = addr 값)
//   읽기: 기록 값과 비교
//   cs_n=1 → rdata = High-Z 확인
//
// [TC2] NPU Identity Matrix 테스트 (SRAM weight buffer 포함)
//   W = 8×8 단위행렬(Identity), A = [1,2,3,4,5,6,7,8], scale=0
//   기대 결과: C[j] = A[j] (identity × A = A)
//   이유: 이 조건이 성립하려면 SRAM write(LOAD_W_DMA) → SRAM read(LOAD_W_SA)
//         → wt_col 전달 → PE weight_reg 로딩 → MAC 계산 전체 경로가 올바라야 함
//
// [TC3] NPU Stress 테스트 (ReLU + 클램프)
//   케이스3: A=-50, W=1 → Σ=-400 → ReLU → 0
//   케이스4: W=0 → Σ=0 → C=0
// =============================================================================
`timescale 1ns/1ps

module tb_sram_sim;

localparam CLK_PERIOD = 5;    // 200 MHz
localparam SA         = 8;
localparam MEM_BYTES  = 4096;

// 결과 카운터
integer pass_cnt = 0, fail_cnt = 0;

logic clk = 0, rst_n;
always #(CLK_PERIOD/2) clk = ~clk;

task automatic check;
    input string msg;
    input logic  cond;
    if (cond) begin
        $display("[PASS] %s", msg);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL] %s", msg);
        fail_cnt = fail_cnt + 1;
    end
endtask

// ===========================================================================
// TC1: sram_sp 단독
// ===========================================================================
logic        s_cs_n = 1, s_we_n = 1;
logic [2:0]  s_addr = 0;
logic [63:0] s_wdata = 0, s_rdata;

sram_sp #(.DEPTH(8), .WIDTH(64), .ADDR_W(3)) u_sram_tc1 (
    .clk(clk), .cs_n(s_cs_n), .we_n(s_we_n),
    .addr(s_addr), .wdata(s_wdata), .rdata(s_rdata)
);

task tc1_sram_basic;
    logic [63:0] exp_val;
    string msg;
    $display("\n=== TC1: sram_sp 기본 동작 ===");

    // 쓰기: addr a → 모든 byte = a (64-bit에 같은 패턴 8번 반복)
    for (integer a = 0; a < 8; a++) begin
        @(negedge clk);
        s_cs_n  = 0; s_we_n = 0;
        s_addr  = a[2:0];
        s_wdata = {8{8'(a)}};   // addr=2 → 64'h0202020202020202
        @(posedge clk); #1;     // SRAM posedge 캡처
    end
    s_cs_n = 1; s_we_n = 1;
    @(posedge clk); #1;

    // 읽기 및 검증
    for (integer a = 0; a < 8; a++) begin
        @(negedge clk);
        s_cs_n = 0; s_we_n = 1; s_addr = a[2:0]; #1;
        exp_val = {8{8'(a)}};
        $sformat(msg, "sram_sp[addr=%0d] read=0x%h exp=0x%h", a, s_rdata, exp_val);
        check(msg, s_rdata === exp_val);
    end
    s_cs_n = 1; #1;

    // cs_n=1 → High-Z 확인 (=== 'z 비교)
    check("cs_n=1 → rdata=High-Z", s_rdata === {64{1'bz}});
endtask

// ===========================================================================
// TC2/TC3: Full NPU (npu_top_ws + inline DRAM BFM)
// ===========================================================================
localparam [31:0] WGT_ADDR = 32'h0000_0000;
localparam [31:0] ACT_ADDR = 32'h0000_0100;
localparam [31:0] OUT_ADDR = 32'h0000_0200;

// APB 신호
logic [31:0] paddr = 0; logic psel=0, penable=0, pwrite=0;
logic [31:0] pwdata=0, prdata; logic pready;

// AXI4 신호 (DUT ↔ inline DRAM BFM)
logic [31:0] araddr; logic [7:0] arlen; logic [2:0] arsize; logic [1:0] arburst;
logic arvalid, arready;
// rlast는 wire(combinatorial): 동일 always 블록 내에서
// rlast<=1 과 rlast<=0 이 같은 posedge에 스케줄되면 LRM §10.4.2에 의해
// 프로그램 순서상 나중인 rlast<=0이 항상 이겨 rlast가 절대 1이 안 되는 버그 방지.
// assign 으로 구동하면 rd_cnt==rd_total인 순간 즉시 1 → DMA 엔진이 정상 감지.
wire  [63:0] rdata; wire  [1:0] rresp; wire  rlast; wire  rvalid; logic rready;
logic [31:0] awaddr; logic [7:0] awlen; logic [2:0] awsize; logic [1:0] awburst;
logic awvalid, awready;
logic [63:0] wdata; logic [7:0] wstrb; logic wlast, wvalid, wready;
logic [1:0] bresp; logic bvalid, bready;

// DUT: npu_top_ws (control_unit.u_sram_wgt 포함)
npu_top_ws #(.SA_SIZE(SA), .DATA_W(8), .ACC_W(32)) u_dut (
    .clk(clk), .rst_n(rst_n),
    .paddr({20'b0,paddr[11:0]}), .psel(psel), .penable(penable),
    .pwrite(pwrite), .pwdata(pwdata), .prdata(prdata), .pready(pready),
    .m_araddr(araddr), .m_arlen(arlen),   .m_arsize(arsize),
    .m_arburst(arburst), .m_arvalid(arvalid), .m_arready(arready),
    .m_rdata(rdata),   .m_rresp(rresp),   .m_rlast(rlast),
    .m_rvalid(rvalid), .m_rready(rready),
    .m_awaddr(awaddr), .m_awlen(awlen),   .m_awsize(awsize),
    .m_awburst(awburst), .m_awvalid(awvalid), .m_awready(awready),
    .m_wdata(wdata),   .m_wstrb(wstrb),   .m_wlast(wlast),
    .m_wvalid(wvalid), .m_wready(wready),
    .m_bresp(bresp),   .m_bvalid(bvalid), .m_bready(bready)
);

// 내부 DRAM 메모리 배열 (계층적 참조 가능)
reg [7:0] dram_mem [0:MEM_BYTES-1];
integer di;
initial for (di=0; di<MEM_BYTES; di=di+1) dram_mem[di] = 8'h00;

// rdata 조합 논리 (핵심 수정):
// 기존 registered rdata의 버그:
//   posedge T에서 rdata <= data[rd_cnt] AND rd_cnt <= rd_cnt+1 동시 실행(NBA).
//   → 다음 사이클 rdata = data[rd_cnt_OLD], 하지만 beat_cnt는 이미 rd_cnt_NEW.
//   → SRAM[n] = W[n-1]: 1-beat 오프셋 발생.
// 수정: rdata를 combinatorial로 → rd_cnt 변경 즉시 반영.
//   posedge T에서 rd_cnt NBA 적용 후, rdata가 즉시 data[rd_cnt_NEW]로 갱신.
//   T+1에서 beat_cnt도 rd_cnt_NEW와 동일 → SRAM[n] = W[n] ✓
reg [31:0]  rd_base_r;   // registered base address
reg [7:0]   rd_cnt_r;    // registered beat counter
reg         rd_rvalid;   // registered valid

// rdata: combinatorial (rd_cnt_r 변경 즉시 반영)
assign rdata = {dram_mem[rd_base_r + rd_cnt_r*8 + 7],
                dram_mem[rd_base_r + rd_cnt_r*8 + 6],
                dram_mem[rd_base_r + rd_cnt_r*8 + 5],
                dram_mem[rd_base_r + rd_cnt_r*8 + 4],
                dram_mem[rd_base_r + rd_cnt_r*8 + 3],
                dram_mem[rd_base_r + rd_cnt_r*8 + 2],
                dram_mem[rd_base_r + rd_cnt_r*8 + 1],
                dram_mem[rd_base_r + rd_cnt_r*8 + 0]};

assign rvalid = rd_rvalid;  // wire alias for consistency

assign arready = 1'b1;

reg        rd_state_r = 0;   // 0=RD_IDLE, 1=RD_BUSY
reg [7:0]  rd_total_r;
// rd_base_r, rd_cnt_r, rd_rvalid declared above with assigns

// rlast: combinatorial (rdata와 동일한 이유로 registered 불가)
assign rlast = rd_rvalid && (rd_cnt_r == rd_total_r);
assign rresp  = 2'b00;  // always OKAY

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_rvalid<=0; rd_cnt_r<=0; rd_state_r<=0;
        rd_base_r<=0; rd_total_r<=0;
    end else begin
        case (rd_state_r)
            1'b0: begin  // RD_IDLE
                rd_rvalid <= 0;
                if (arvalid && arready) begin
                    rd_base_r  <= araddr;
                    rd_total_r <= arlen;
                    rd_cnt_r   <= 0;
                    rd_state_r <= 1;
                end
            end
            1'b1: begin  // RD_BUSY
                rd_rvalid <= 1;
                // rdata와 rlast는 combinatorial assign → 건드리지 않음
                // rvalid&&rready: beat 수락
                if (rd_rvalid && rready) begin
                    if (rd_cnt_r == rd_total_r) begin
                        rd_rvalid  <= 0;
                        rd_state_r <= 0;
                    end else rd_cnt_r <= rd_cnt_r + 1;
                end
            end
        endcase
    end
end

// ---------------------------------------------------------------------------
// Inline AXI4 Slave BFM — Write FSM
// ---------------------------------------------------------------------------
assign awready = 1'b1;
assign wready  = 1'b1;

reg [1:0]  wr_state = 0;   // 0=WR_IDLE, 1=WR_DATA, 2=WR_RESP
reg [31:0] wr_base;
reg [7:0]  wr_cnt;
integer wb;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bvalid<=0; bresp<=0; wr_cnt<=0; wr_state<=0;
    end else begin
        case (wr_state)
            2'd0: begin  // WR_IDLE
                bvalid <= 0;
                if (awvalid && awready) begin
                    wr_base  <= awaddr;
                    wr_cnt   <= 0;
                    wr_state <= 1;
                end
            end
            2'd1: begin  // WR_DATA
                if (wvalid && wready) begin
                    // wstrb 체크: 유효 바이트만 저장
                    for (wb=0; wb<8; wb=wb+1)
                        if (wstrb[wb]) dram_mem[wr_base+wr_cnt*8+wb] <= wdata[wb*8+:8];
                    wr_cnt <= wr_cnt + 1;
                    if (wlast) begin bvalid<=1; bresp<=0; wr_state<=2; end
                end
            end
            2'd2: begin  // WR_RESP
                if (bvalid && bready) begin bvalid<=0; wr_state<=0; end
            end
        endcase
    end
end

// ---------------------------------------------------------------------------
// APB 마스터 태스크
// ---------------------------------------------------------------------------
task automatic apb_write;
    input [11:0] addr;
    input [31:0] data;
    @(negedge clk);
    paddr={20'b0,addr}; pwdata=data; pwrite=1; psel=1; penable=0;
    @(negedge clk); penable=1;
    @(posedge clk); while(!pready) @(posedge clk);
    @(negedge clk); psel=0; penable=0; pwrite=0;
endtask

// ---------------------------------------------------------------------------
// TC2: NPU Identity Matrix
// ---------------------------------------------------------------------------
task tc2_npu_identity;
    reg signed [7:0] wgt [0:SA*SA-1];
    reg signed [7:0] act [0:SA-1];
    reg signed [7:0] golden [0:SA-1];
    reg signed [7:0] actual;
    integer err_cnt, tc, k, j;
    string msg;

    $display("\n=== TC2: NPU Identity Matrix (SRAM weight buffer 검증) ===");
    $display("    W=I, A=[1..8], scale=0 → 기대: C[j]=A[j]");

    // Weight = Identity matrix (W[k][j] = 1 if k==j, else 0)
    for (k=0; k<SA; k=k+1)
        for (j=0; j<SA; j=j+1)
            wgt[k*SA+j] = (k==j) ? 8'sd1 : 8'sd0;

    // Activation = [1,2,3,4,5,6,7,8]
    for (k=0; k<SA; k=k+1) act[k] = k+1;

    // Golden = act (Identity × A = A, scale=0, ReLU pass, clamp pass)
    for (j=0; j<SA; j=j+1) golden[j] = act[j];

    // DRAM 사전 로드
    for (k=0; k<SA; k=k+1)
        for (j=0; j<SA; j=j+1)
            dram_mem[WGT_ADDR+k*SA+j] = wgt[k*SA+j];
    for (k=0; k<SA; k=k+1)
        dram_mem[ACT_ADDR+k] = act[k];

    $display("    DRAM 로드: W[0][0]=%0d, A[0]=%0d",
             $signed(dram_mem[WGT_ADDR]), $signed(dram_mem[ACT_ADDR]));

    // APB 설정 후 start
    apb_write(12'h00, WGT_ADDR);
    apb_write(12'h04, ACT_ADDR);
    apb_write(12'h08, OUT_ADDR);
    apb_write(12'h0C, 32'd0);    // scale=0
    apb_write(12'h10, 32'h1);    // start=1

    $display("    start 어서트 → FSM IDLE→LOAD_W_DMA");

    // done 대기 (타임아웃 500사이클)
    // 주의: done은 1사이클 펄스 → APB write 직후 즉시 폴링 시작해야 놓치지 않음
    // 이론 소요: LOAD_W_DMA(9) + LOAD_W_SA(8) + LOAD_A_DMA(3) + COMPUTE+DRAIN(16) + STORE(7) ≈ 55사이클
    // 이론 소요 ≈ 8(LOAD_W_DMA) + 8(LOAD_W_SA) + 3(LOAD_A_DMA) + 16(COMPUTE+DRAIN) + 5(STORE) = ~40사이클
    tc = 0;
    @(posedge clk);
    while (!u_dut.u_ctrl.done && tc < 500) begin
        @(posedge clk); tc = tc + 1;
    end

    check("NPU done 수신 (500사이클 이내)", tc < 500);
    if (tc >= 500) begin
        $display("    TIMEOUT! FSM 확인 필요"); $finish;
    end
    $display("    done 수신. 소요=%0d사이클", tc);

    repeat(2) @(posedge clk);  // 안정화

    // 출력 검증
    err_cnt = 0;
    for (j=0; j<SA; j=j+1) begin
        actual = dram_mem[OUT_ADDR+j];
        if ($signed(actual) !== $signed(golden[j])) begin
            $display("    MISMATCH out[%0d]: DUT=%0d, GOLDEN=%0d",
                     j, $signed(actual), $signed(golden[j]));
            err_cnt = err_cnt + 1;
        end
    end
    check("Golden 비교: I×A = A (전체 8개)", err_cnt == 0);
    if (err_cnt == 0) begin
        $display("    out[0]=%0d, out[7]=%0d (= act[0], act[7] 각각)",
                 $signed(dram_mem[OUT_ADDR]), $signed(dram_mem[OUT_ADDR+SA-1]));
        $display("    ✓ SRAM write(LOAD_W_DMA) → SRAM read(LOAD_W_SA) → MAC → 출력 경로 정상");
    end
endtask

// ---------------------------------------------------------------------------
// TC3: NPU Stress (ReLU + W=0)
// ---------------------------------------------------------------------------
task tc3_npu_stress;
    integer k, j, tc, err_cnt;

    $display("\n=== TC3: NPU Stress — ReLU 검증 ===");
    $display("    A=-50, W=1, scale=7 → Σ=-400 → ReLU → C=0");

    // W=1 (모든 원소), A=-50
    for (k=0; k<SA; k=k+1)
        for (j=0; j<SA; j=j+1)
            dram_mem[WGT_ADDR+k*SA+j] = 8'sd1;
    for (k=0; k<SA; k=k+1)
        dram_mem[ACT_ADDR+k] = -8'sd50;

    apb_write(12'h00, WGT_ADDR);
    apb_write(12'h04, ACT_ADDR);
    apb_write(12'h08, OUT_ADDR);
    apb_write(12'h0C, 32'd7);   // scale=7
    apb_write(12'h10, 32'h1);

    tc = 0; @(posedge clk);
    while (!u_dut.u_ctrl.done && tc < 500) begin @(posedge clk); tc=tc+1; end
    check("TC3 ReLU: done 수신", tc < 500);

    repeat(2) @(posedge clk);
    err_cnt = 0;
    for (j=0; j<SA; j=j+1) begin
        // 기대: Σ = 8×(-50)×1 = -400 < 0 → ReLU → 0
        if ($signed(dram_mem[OUT_ADDR+j]) !== 8'sd0) begin
            $display("    MISMATCH out[%0d]=%0d (기대: 0)",
                     j, $signed(dram_mem[OUT_ADDR+j]));
            err_cnt = err_cnt + 1;
        end
    end
    check("TC3 ReLU: 음수 입력 → 출력 all-0", err_cnt == 0);

    // W=0 케이스
    $display("\n=== TC3: W=0 → C=0 ===");
    for (k=0; k<SA; k=k+1)
        for (j=0; j<SA; j=j+1)
            dram_mem[WGT_ADDR+k*SA+j] = 8'sd0;
    for (k=0; k<SA; k=k+1)
        dram_mem[ACT_ADDR+k] = 8'sd127;

    apb_write(12'h00, WGT_ADDR);
    apb_write(12'h04, ACT_ADDR);
    apb_write(12'h08, OUT_ADDR);
    apb_write(12'h0C, 32'd7);
    apb_write(12'h10, 32'h1);

    tc = 0; @(posedge clk);
    while (!u_dut.u_ctrl.done && tc < 500) begin @(posedge clk); tc=tc+1; end
    check("TC3 W=0: done 수신", tc < 500);

    repeat(2) @(posedge clk);
    err_cnt = 0;
    for (j=0; j<SA; j=j+1)
        if ($signed(dram_mem[OUT_ADDR+j]) !== 8'sd0) err_cnt = err_cnt + 1;
    check("TC3 W=0: 출력 all-0", err_cnt == 0);
endtask

// ===========================================================================
// 메인 시퀀스
// ===========================================================================
initial begin
    $dumpfile("tb_sram.vcd");
    $dumpvars(0, tb_sram_sim);

    psel=0; penable=0; pwrite=0; paddr=0; pwdata=0;
    s_cs_n=1; s_we_n=1; s_addr=0; s_wdata=0;

    // 리셋 (10사이클)
    rst_n = 0;
    repeat(10) @(posedge clk);
    @(negedge clk); rst_n = 1;
    @(posedge clk);

    tc1_sram_basic();
    tc2_npu_identity();
    tc3_npu_stress();

    @(posedge clk);
    $display("\n================================================");
    $display("  시뮬레이션 완료: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
        $display("  결과: ALL PASS");
    else
        $display("  결과: FAIL %0d개 — 위 로그 확인", fail_cnt);
    $display("================================================\n");
    $finish;
end

// 1ms 워치독
initial begin
    #1_000_000;
    $display("[WATCHDOG] 1ms 초과 종료");
    $finish;
end

endmodule
