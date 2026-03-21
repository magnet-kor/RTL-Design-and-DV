// =============================================================================
// npu_scoreboard.sv  —  Golden Model 비교기
//
// [역할]
//   monitor → write() 수신 → compute_golden() → compare() → PASS/FAIL
//
// [Golden Model 연산 (post_proc.sv와 동일 순서)]
//   Step1. INT32 누적: acc = Σ_k A[k] × W[k*8+j]
//   Step2. ReLU:       acc = max(0, acc)
//   Step3. Scale:      acc = acc >>> scale  (산술 우시프트)
//   Step4. Clamp:      acc = clip(acc, -128, 127)
//   Step5. INT8 출력
//
// [SV integer 사용 이유]
//   integer는 32-bit signed → >>> 산술 시프트 보장.
//   logic unsigned로 받으면 >>> 가 논리 시프트 → 부호 오류 발생.
// =============================================================================
`ifndef NPU_SCOREBOARD_SV
`define NPU_SCOREBOARD_SV

class npu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(npu_scoreboard)
    localparam int SA = 8;
    uvm_analysis_imp #(npu_seq_item, npu_scoreboard) analysis_export;
    int unsigned pass_cnt=0, fail_cnt=0, total_cnt=0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
    endfunction

    function void write(npu_seq_item item);
        compute_golden(item);
        compare(item);
    endfunction

    function automatic void compute_golden(npu_seq_item item);
        for (int j = 0; j < SA; j++) begin
            automatic integer acc = 0;
            for (int k = 0; k < SA; k++)
                acc += $signed(item.A[k]) * $signed(item.W[k*SA+j]);
            if (acc < 0) acc = 0;           // ReLU
            acc = acc >>> item.scale;        // 산술 우시프트
            if      (acc >  127) acc =  127; // 클램프 상한
            else if (acc < -128) acc = -128; // 클램프 하한
            item.expected[j] = acc[7:0];
        end
    endfunction

    function automatic void compare(npu_seq_item item);
        bit pass = 1'b1;
        total_cnt++;
        for (int j = 0; j < SA; j++) begin
            if (item.actual_out[j] !== item.expected[j]) begin
                pass = 1'b0;
                `uvm_error("SB", $sformatf(
                    "MISMATCH C[%0d]: actual=%0d expected=%0d | scale=%0d",
                    j, $signed(item.actual_out[j]), $signed(item.expected[j]), item.scale))
            end
        end
        if (pass) begin
            pass_cnt++;
            `uvm_info("SB",$sformatf("[PASS #%0d] all 8 outputs match (scale=%0d)",
                      pass_cnt, item.scale), UVM_LOW)
        end else begin
            fail_cnt++;
            `uvm_error("SB",$sformatf("[FAIL #%0d] mismatch%s",fail_cnt,item.convert2string()))
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SB",$sformatf(
            "\n========================================\n"
          + "  Scoreboard Summary\n"
          + "  Total : %0d\n"
          + "  PASS  : %0d\n"
          + "  FAIL  : %0d\n"
          + "========================================",
            total_cnt, pass_cnt, fail_cnt), UVM_NONE)
        if (fail_cnt > 0) `uvm_error("SB","TEST FAILED")
        else              `uvm_info("SB","TEST PASSED",UVM_NONE)
    endfunction
endclass
`endif
