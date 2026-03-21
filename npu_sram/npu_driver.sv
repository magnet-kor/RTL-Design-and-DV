// =============================================================================
// npu_driver.sv  —  UVM Driver
//
// [역할] seq_item → DUT 구동 (3단계)
//   Phase1. DRAM 사전 로드: dram_vif.write_byte()로 W, A 기록
//           주소: wgt_addr + k*SA + j (row-major), act_addr + k
//   Phase2. APB 레지스터 설정: wgt/act/out_addr, scale, start
//           start는 마지막에 써야 함 (모든 주소 설정 완료 후 실행)
//   Phase3. done 대기: vif.wait_done() → NPU 완료 확인
//
// [TLM 연결]
//   seq_item_port → seqr.seq_item_export (get_next_item / item_done)
// =============================================================================
`ifndef NPU_DRIVER_SV
`define NPU_DRIVER_SV

class npu_driver extends uvm_driver #(npu_seq_item);
    `uvm_component_utils(npu_driver)
    localparam int SA = 8;
    virtual npu_if           vif;
    virtual dram_backdoor_if dram_vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual npu_if)::get(this,"","npu_vif",vif))
            `uvm_fatal("CFG","npu_vif not found in config_db")
        if (!uvm_config_db #(virtual dram_backdoor_if)::get(this,"","dram_vif",dram_vif))
            `uvm_fatal("CFG","dram_vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        npu_seq_item item;
        // APB idle 초기화
        vif.psel=1'b0; vif.penable=1'b0; vif.pwrite=1'b0;
        vif.paddr='0; vif.pwdata='0;
        @(posedge vif.rst_n);
        repeat(5) @(posedge vif.clk);
        forever begin
            seq_item_port.get_next_item(item);
            `uvm_info("DRV",$sformatf("Driving item: scale=%0d",item.scale),UVM_MEDIUM)
            drive_item(item);
            seq_item_port.item_done();
        end
    endtask

    task automatic drive_item(input npu_seq_item item);
        // Phase1: DRAM에 W/A 사전 로드
        `uvm_info("DRV","Phase1: pre-loading W & A",UVM_HIGH)
        for (int k=0;k<SA;k++)
            for (int j=0;j<SA;j++)
                dram_vif.write_byte(int'(item.wgt_addr)+k*SA+j, item.W[k*SA+j]);
        for (int k=0;k<SA;k++)
            dram_vif.write_byte(int'(item.act_addr)+k, item.A[k]);
        // Phase2: APB 레지스터 설정 (start는 반드시 마지막)
        `uvm_info("DRV","Phase2: APB config",UVM_HIGH)
        vif.apb_write(32'h00, item.wgt_addr);
        vif.apb_write(32'h04, item.act_addr);
        vif.apb_write(32'h08, item.out_addr);
        vif.apb_write(32'h0C, {27'b0,item.scale});
        vif.apb_write(32'h10, 32'h1);  // start=1 (self-clearing)
        // Phase3: done 대기
        `uvm_info("DRV","Phase3: waiting for done",UVM_HIGH)
        vif.wait_done();
        `uvm_info("DRV","done received",UVM_LOW)
    endtask
endclass
`endif
