// =============================================================================
// dram_backdoor_if.sv  —  DRAM 공유 메모리 인터페이스
//
// [역할]
//   dram_model(AXI4 Slave BFM)과 UVM driver/monitor가 동일한 메모리 배열 공유.
//   SystemVerilog interface로 선언 → 모듈 포트로 전달(UVM testbench에서 사용).
//
// [사용 패턴]
//   UVM driver  → write_byte(addr, data) : W/A 사전 로드 (DUT 시작 전)
//   UVM monitor → read_byte(addr)        : done 후 DUT 출력 읽기
//   dram_model  → read_qword(addr)       : AXI4 R 채널 beat 데이터 공급
//   dram_model  → write_qword(addr,data) : AXI4 W 채널 beat 데이터 저장
//
// [메모리 레이아웃 (기본 주소)]
//   0x0000_0000 : Weight  64B  (8×8 INT8, row-major W[k*8+j])
//   0x0000_0100 : Act      8B  (A[0..7] INT8)
//   0x0000_0200 : Output   8B  (C[0..7] INT8, done 후 DUT 기록)
//
// [주의] dram_model이 interface를 포트로 받기 때문에
//        VCS/Questasim에서만 완전 지원. iverilog는 interface 포트 미지원.
// =============================================================================
interface dram_backdoor_if #(
    parameter int MEM_BYTES = 4096
)(input logic clk);

    logic [7:0] mem [0:MEM_BYTES-1];
    initial foreach (mem[i]) mem[i] = 8'h00;

    // 바이트 쓰기 (driver: W/A 사전 로드)
    task automatic write_byte(input int addr, input logic [7:0] data);
        if (addr >= 0 && addr < MEM_BYTES) mem[addr] = data;
        else $error("[DRAM_IF] write OOB addr=0x%0h", addr);
    endtask

    // 바이트 벌크 쓰기
    task automatic write_block(input int start_addr,
                                input logic [7:0] data [], input int len);
        for (int i = 0; i < len; i++) write_byte(start_addr + i, data[i]);
    endtask

    // 바이트 읽기 (monitor: 결과 읽기)
    function automatic logic [7:0] read_byte(input int addr);
        if (addr >= 0 && addr < MEM_BYTES) return mem[addr];
        else begin $error("[DRAM_IF] read OOB addr=0x%0h", addr); return 8'hxx; end
    endfunction

    // 64-bit 읽기 (dram_model: AXI4 R채널 beat, little-endian)
    function automatic logic [63:0] read_qword(input int addr);
        logic [63:0] q;
        for (int b = 0; b < 8; b++)
            q[b*8 +: 8] = (addr+b < MEM_BYTES) ? mem[addr+b] : 8'h00;
        return q;
    endfunction

    // 64-bit 쓰기 (dram_model: AXI4 W채널 beat)
    task automatic write_qword(input int addr, input logic [63:0] data);
        for (int b = 0; b < 8; b++)
            if (addr+b < MEM_BYTES) mem[addr+b] = data[b*8 +: 8];
    endtask

endinterface
