// =============================================================================
// npu_test.sv  —  UVM 테스트 클래스 3종
//
// [실행 방법]
//   +UVM_TESTNAME=npu_identity_test  (배선/파이프라인 오류 탐지, 1회)
//   +UVM_TESTNAME=npu_random_test    (랜덤, 20회)
//   +UVM_TESTNAME=npu_stress_test    (extreme 케이스 4종)
//
// [base_test 역할]
//   env 생성 + run_seq() 공통 태스크 제공
//   → 하위 클래스는 run_phase에서 시퀀스 종류만 교체
// =============================================================================
`ifndef NPU_TEST_SV
`define NPU_TEST_SV

class npu_base_test extends uvm_test;
    `uvm_component_utils(npu_base_test)
    npu_env env;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = npu_env::type_id::create("env", this);
    endfunction
    task automatic run_seq(uvm_sequence #(npu_seq_item) seq);
        seq.start(env.agt.seqr);
    endtask
endclass

class npu_identity_test extends npu_base_test;
    `uvm_component_utils(npu_identity_test)
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    task run_phase(uvm_phase phase);
        npu_identity_seq seq;
        phase.raise_objection(this);
        seq = npu_identity_seq::type_id::create("seq");
        seq.num_txns = 1;
        `uvm_info("TEST","=== npu_identity_test START ===",UVM_NONE)
        run_seq(seq);
        `uvm_info("TEST","=== npu_identity_test DONE ===",UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass

class npu_random_test extends npu_base_test;
    `uvm_component_utils(npu_random_test)
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    task run_phase(uvm_phase phase);
        npu_random_seq seq;
        phase.raise_objection(this);
        seq = npu_random_seq::type_id::create("seq");
        seq.num_txns = 20;
        `uvm_info("TEST","=== npu_random_test START (20 txns) ===",UVM_NONE)
        run_seq(seq);
        `uvm_info("TEST","=== npu_random_test DONE ===",UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass

class npu_stress_test extends npu_base_test;
    `uvm_component_utils(npu_stress_test)
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    task run_phase(uvm_phase phase);
        npu_stress_seq seq;
        phase.raise_objection(this);
        seq = npu_stress_seq::type_id::create("seq");
        `uvm_info("TEST","=== npu_stress_test START (4 extreme cases) ===",UVM_NONE)
        run_seq(seq);
        `uvm_info("TEST","=== npu_stress_test DONE ===",UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass
`endif
