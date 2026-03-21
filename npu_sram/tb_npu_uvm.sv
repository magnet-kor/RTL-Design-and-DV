// =============================================================================
// tb_npu_uvm.sv  —  UVM 최상위 테스트벤치
//
// [인스턴스 구성]
//   npu_top_ws       : DUT (control_unit 내부에 sram_sp u_sram_wgt 포함)
//   dram_model       : AXI4 Slave BFM, bkdoor를 통해 메모리 공유
//   npu_if           : APB + 상태 신호 인터페이스 (virtual → UVM config_db)
//   dram_backdoor_if : 공유 메모리 (virtual → UVM config_db)
//
// [DUT-DRAM 연결 방식]
//   u_dut.m_araddr → u_dram.s_araddr 계층적 참조로 직결
//   이유: npu_top_ws 포트를 SystemVerilog wire로 노출하고
//         u_dram 포트를 tb 레벨 wire로 연결하면 양방향 연결 간편
//
// [UVM 시작]
//   config_db에 virtual interface 등록 후 run_test() 호출
//   +UVM_TESTNAME=npu_identity_test|npu_random_test|npu_stress_test
//
// [실행 예시 — VCS]
//   vcs -sverilog -ntb_opts uvm-1.2 tb_npu_uvm.sv npu_top_ws.sv ... \
//       +UVM_TESTNAME=npu_random_test +UVM_VERBOSITY=UVM_MEDIUM
// =============================================================================
`timescale 1ns/1ps
`include "uvm_macros.svh"

`include "npu_seq_item.sv"
`include "npu_driver.sv"
`include "npu_monitor.sv"
`include "npu_scoreboard.sv"
`include "npu_coverage.sv"
`include "npu_agent_env.sv"
`include "npu_sequences.sv"
`include "npu_test.sv"

import uvm_pkg::*;

module tb_npu_uvm;
    localparam int CLK_PERIOD  = 5;    // 200MHz
    localparam int RESET_CYCLE = 20;

    logic clk = 1'b0, rst_n;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        rst_n = 1'b0;
        repeat(RESET_CYCLE) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
    end

    npu_if           npu_vif (.clk(clk), .rst_n(rst_n));
    dram_backdoor_if dram_vif(.clk(clk));

    // DUT: npu_top_ws (SRAM weight buffer 포함)
    npu_top_ws #(.SA_SIZE(8),.DATA_W(8),.ACC_W(32)) u_dut (
        .clk(clk),.rst_n(rst_n),
        .paddr   (npu_vif.paddr),   .psel    (npu_vif.psel),
        .penable (npu_vif.penable), .pwrite  (npu_vif.pwrite),
        .pwdata  (npu_vif.pwdata),  .prdata  (npu_vif.prdata),
        .pready  (npu_vif.pready),
        // AXI4: 계층적 참조로 dram_model과 직결
        .m_araddr(u_dram.s_araddr),.m_arlen(u_dram.s_arlen),
        .m_arsize(u_dram.s_arsize),.m_arburst(u_dram.s_arburst),
        .m_arvalid(u_dram.s_arvalid),.m_arready(u_dram.s_arready),
        .m_rdata(u_dram.s_rdata),.m_rresp(u_dram.s_rresp),
        .m_rlast(u_dram.s_rlast),.m_rvalid(u_dram.s_rvalid),
        .m_rready(u_dram.s_rready),
        .m_awaddr(u_dram.s_awaddr),.m_awlen(u_dram.s_awlen),
        .m_awsize(u_dram.s_awsize),.m_awburst(u_dram.s_awburst),
        .m_awvalid(u_dram.s_awvalid),.m_awready(u_dram.s_awready),
        .m_wdata(u_dram.s_wdata),.m_wstrb(u_dram.s_wstrb),
        .m_wlast(u_dram.s_wlast),.m_wvalid(u_dram.s_wvalid),
        .m_wready(u_dram.s_wready),
        .m_bresp(u_dram.s_bresp),.m_bvalid(u_dram.s_bvalid),
        .m_bready(u_dram.s_bready)
    );

    // DUT 내부 상태 신호 → npu_if 연결
    assign npu_vif.npu_done = u_dut.u_ctrl.done;
    assign npu_vif.npu_busy = u_dut.u_ctrl.busy;

    // DRAM BFM
    dram_model u_dram (
        .clk(clk),.rst_n(rst_n),.bkdoor(dram_vif),
        .s_araddr(),.s_arlen(),.s_arsize(),.s_arburst(),
        .s_arvalid(),.s_arready(),
        .s_rdata(),.s_rresp(),.s_rlast(),.s_rvalid(),.s_rready(),
        .s_awaddr(),.s_awlen(),.s_awsize(),.s_awburst(),
        .s_awvalid(),.s_awready(),
        .s_wdata(),.s_wstrb(),.s_wlast(),.s_wvalid(),.s_wready(),
        .s_bresp(),.s_bvalid(),.s_bready()
    );

    initial begin
        uvm_config_db #(virtual npu_if)::set(null,"uvm_test_top.*","npu_vif",npu_vif);
        uvm_config_db #(virtual dram_backdoor_if)::set(null,"uvm_test_top.*","dram_vif",dram_vif);
        $dumpfile("tb_npu_uvm.vcd");
        $dumpvars(0, tb_npu_uvm);
        run_test();
    end

    initial begin
        #10_000_000;
        `uvm_fatal("TB","WATCHDOG: simulation timeout")
    end
endmodule
