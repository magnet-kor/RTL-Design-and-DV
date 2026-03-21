// =============================================================================
// npu_agent_env.sv  —  UVM Agent + Environment
//
// [npu_agent]
//   UVM_ACTIVE: driver + monitor + sequencer 모두 생성
//   UVM_PASSIVE: monitor만 생성 (post-silicon 재사용 등)
//   mon.ap → agent.ap 전달 → env가 subscribe
//
// [npu_env]
//   agent + scoreboard + coverage 조합.
//   connect_phase: agent.ap → sb.analysis_export AND cov.analysis_export
//   TLM fan-out으로 scoreboard와 coverage가 동일 seq_item 동시 수신
// =============================================================================
`ifndef NPU_AGENT_SV
`define NPU_AGENT_SV

class npu_agent extends uvm_agent;
    `uvm_component_utils(npu_agent)
    npu_driver    drv;
    npu_monitor   mon;
    uvm_sequencer #(npu_seq_item) seqr;
    uvm_analysis_port #(npu_seq_item) ap;

    function new(string name, uvm_component parent); super.new(name,parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap  = new("ap", this);
        mon = npu_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            drv  = npu_driver::type_id::create("drv", this);
            seqr = uvm_sequencer #(npu_seq_item)::type_id::create("seqr", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        if (get_is_active() == UVM_ACTIVE)
            drv.seq_item_port.connect(seqr.seq_item_export);
        mon.ap.connect(ap);  // monitor → agent ap 전달
    endfunction
endclass
`endif

`ifndef NPU_ENV_SV
`define NPU_ENV_SV

class npu_env extends uvm_env;
    `uvm_component_utils(npu_env)
    npu_agent      agt;
    npu_scoreboard sb;
    npu_coverage   cov;

    function new(string name, uvm_component parent); super.new(name,parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = npu_agent::type_id::create("agt", this);
        sb  = npu_scoreboard::type_id::create("sb",  this);
        cov = npu_coverage::type_id::create("cov",   this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agt.ap.connect(sb.analysis_export);   // → golden 비교
        agt.ap.connect(cov.analysis_export);  // → 커버리지 수집
    endfunction
endclass
`endif
