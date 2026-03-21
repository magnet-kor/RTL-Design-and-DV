// =============================================================================
// npu_coverage.sv  —  기능 커버리지 수집기
//
// [커버포인트 설계 근거]
//   cp_scale(7~10): 포화/정상 두 영역 모두 커버 확인
//   cp_w_zero/max/min: Weight 경계값 통과 여부 (곱셈기 corner case)
//   cp_a_zero/max: Activation 경계값 (0×W=0, 127×W=최대)
//   cp_out_sat_high: 클램프 실제 발동 케이스 커버 (post_proc 검증)
//   cp_relu_active: ReLU가 실제 음수를 잘라낸 케이스 커버
//
// [크로스 cx_scale_sat]
//   scale×포화 여부 조합: "작은 scale에서 포화 발동, 큰 scale에서 정상"
//   이 패턴이 커버되면 scale 조정 로직이 올바르다는 증거
//
// [uvm_subscriber 사용 이유]
//   uvm_subscriber = uvm_component + analysis_export 자동 내장
//   → env.connect_phase에서 agent.ap.connect(cov.analysis_export) 1줄로 연결
// =============================================================================
`ifndef NPU_COVERAGE_SV
`define NPU_COVERAGE_SV

class npu_coverage extends uvm_subscriber #(npu_seq_item);
    `uvm_component_utils(npu_coverage)
    localparam int SA = 8;
    npu_seq_item item;

    covergroup cg_npu;
        cp_scale: coverpoint item.scale {
            bins s7={7}; bins s8={8}; bins s9={9}; bins s10={10};
        }
        cp_w_zero: coverpoint (item.W.sum()==0) {
            bins all_zero={1}; bins nonzero={0};
        }
        cp_w_max: coverpoint (item.W[0]==8'sd127)  { bins max_val={1}; }
        cp_w_min: coverpoint (item.W[0]==-8'sd128) { bins min_val={1}; }
        cp_a_zero: coverpoint (item.A[0]==0)       { bins zero={1}; bins nonzero={0}; }
        cp_a_max:  coverpoint (item.A[0]==8'sd127) { bins max_act={1}; }
        cp_out_sat_high: coverpoint
            (item.expected[0]==8'sd127||item.expected[1]==8'sd127||
             item.expected[2]==8'sd127||item.expected[3]==8'sd127) {
            bins saturated={1}; bins normal={0};
        }
        // ReLU 발동: A<0인데 expected=0 → 음수가 실제로 잘렸음을 확인
        cp_relu_active: coverpoint (item.expected[0]==0 && item.A[0]<0) {
            bins relu_fired={1};
        }
        cx_scale_sat: cross cp_scale, cp_out_sat_high;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_npu = new();
    endfunction

    function void write(npu_seq_item t);
        item = t;
        cg_npu.sample();
        `uvm_info("COV",$sformatf("coverage=%.1f%%",cg_npu.get_coverage()),UVM_HIGH)
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV",$sformatf("Final coverage: %.1f%%",cg_npu.get_coverage()),UVM_NONE)
    endfunction
endclass
`endif
