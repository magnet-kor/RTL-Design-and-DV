// =============================================================================
// npu_monitor.sv  —  UVM Monitor (Passive Observer)
//
// [역할]
//   DUT를 구동하지 않고 관찰만. APB 스누핑 → done 감지 → DRAM 읽기 → SB 전달.
//
// [동작 순서]
//   1. APB 버스 스누핑: apb_wr_active 이벤트로 5회 쓰기 감지
//      (driver 순서: wgt_addr → act_addr → out_addr → scale → start)
//   2. npu_done 펄스 대기
//   3. DRAM 백도어 읽기: W, A, 실제 출력(actual_out) 수집
//   4. ap.write(item) → scoreboard & coverage 전달
//
// [apb_wr_active 사용 이유]
//   psel & penable & pwrite & pready = APB access 완료 조건
//   이 신호가 1인 posedge에서만 이벤트 발생 → CPU 주기 낭비 없는 이벤트 기반 감시
// =============================================================================
`ifndef NPU_MONITOR_SV
`define NPU_MONITOR_SV

class npu_monitor extends uvm_monitor;
    `uvm_component_utils(npu_monitor)
    localparam int SA = 8;
    uvm_analysis_port #(npu_seq_item) ap;
    virtual npu_if           vif;
    virtual dram_backdoor_if dram_vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual npu_if)::get(this,"","npu_vif",vif))
            `uvm_fatal("CFG","npu_vif not found")
        if (!uvm_config_db #(virtual dram_backdoor_if)::get(this,"","dram_vif",dram_vif))
            `uvm_fatal("CFG","dram_vif not found")
    endfunction

    task run_phase(uvm_phase phase);
        forever monitor_one_txn();
    endtask

    task automatic monitor_one_txn();
        npu_seq_item item;
        item = npu_seq_item::type_id::create("mon_item");
        // APB 5회 쓰기 스누핑 (wgt_addr, act_addr, out_addr, scale, start 순)
        begin : snoop_loop
            int wr_count = 0;
            while (wr_count < 5) begin
                @(posedge vif.clk iff vif.apb_wr_active);
                case (vif.paddr[5:0])
                    6'h00: item.wgt_addr = vif.pwdata;
                    6'h04: item.act_addr = vif.pwdata;
                    6'h08: item.out_addr = vif.pwdata;
                    6'h0C: item.scale    = vif.pwdata[4:0];
                    6'h10: ;  // start bit: 주소만 카운트
                endcase
                wr_count++;
            end
        end
        `uvm_info("MON",$sformatf("Config: wgt=%0h act=%0h scale=%0d",
                  item.wgt_addr,item.act_addr,item.scale),UVM_HIGH)
        // done 펄스 대기
        @(posedge vif.clk iff vif.npu_done);
        `uvm_info("MON","done detected",UVM_MEDIUM)
        // 1사이클 안정화 후 DRAM 읽기
        @(posedge vif.clk);
        for (int k=0;k<SA;k++)
            for (int j=0;j<SA;j++)
                item.W[k*SA+j] = dram_vif.read_byte(int'(item.wgt_addr)+k*SA+j);
        for (int k=0;k<SA;k++)
            item.A[k] = dram_vif.read_byte(int'(item.act_addr)+k);
        for (int j=0;j<SA;j++)
            item.actual_out[j] = dram_vif.read_byte(int'(item.out_addr)+j);
        `uvm_info("MON",$sformatf("actual[0..3]=%0d %0d %0d %0d",
                  $signed(item.actual_out[0]),$signed(item.actual_out[1]),
                  $signed(item.actual_out[2]),$signed(item.actual_out[3])),UVM_MEDIUM)
        ap.write(item);
    endtask
endclass
`endif
