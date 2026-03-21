// =============================================================================
// npu_seq_item.sv  —  UVM 트랜잭션 (시퀀스 아이템)
//
// [역할]
//   하나의 NPU 추론 요청을 캡슐화하는 UVM sequence_item.
//   driver가 DUT에 stimulus를 인가하고, monitor가 결과를 채워 scoreboard에 전달.
//
// [필드]
//   W[64]   : 8×8 INT8 weight 행렬 (row-major, W[k*8+j])
//   A[8]    : INT8 activation 벡터
//   scale   : post_proc 우시프트 양 (7~10)
//   wgt_addr, act_addr, out_addr: DRAM 주소 (고정 레이아웃)
//   actual_out[8]: monitor가 DRAM에서 읽은 DUT 출력
//   expected[8] : scoreboard가 golden model로 계산한 기대값
//
// [제약 c_scale 근거]
//   INT32 최대값 = 127×127×8 = 129,032 ≈ 2^17
//   scale=7: 129,032>>7=1,008 → 클램프 발동 (포화 검증)
//   scale=10: 129,032>>10=126 → INT8 범위 내 (정상 케이스 검증)
// =============================================================================
`ifndef NPU_SEQ_ITEM_SV
`define NPU_SEQ_ITEM_SV

class npu_seq_item extends uvm_sequence_item;
    `uvm_object_utils(npu_seq_item)

    localparam int SA = 8;

    // Stimulus
    rand logic signed [7:0] W [0:SA*SA-1];
    rand logic signed [7:0] A [0:SA-1];
    rand logic        [4:0] scale;

    // DRAM 주소 (고정)
    logic [31:0] wgt_addr = 32'h0000_0000;
    logic [31:0] act_addr = 32'h0000_0100;
    logic [31:0] out_addr = 32'h0000_0200;

    // Result
    logic signed [7:0] actual_out [0:SA-1];
    logic signed [7:0] expected   [0:SA-1];

    constraint c_scale { scale inside {[7:10]}; }

    function new(string name = "npu_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        string s;
        s = $sformatf("\n  scale=%0d  wgt=0x%0h  act=0x%0h  out=0x%0h\n",
                       scale, wgt_addr, act_addr, out_addr);
        s = {s, "  W[0..7]="};
        for (int i=0;i<SA;i++) s={s,$sformatf("%4d",$signed(W[i]))};
        s = {s, "\n  A      ="};
        for (int k=0;k<SA;k++) s={s,$sformatf("%4d",$signed(A[k]))};
        s = {s, "\n  actual ="};
        for (int j=0;j<SA;j++) s={s,$sformatf("%4d",$signed(actual_out[j]))};
        s = {s, "\n  golden ="};
        for (int j=0;j<SA;j++) s={s,$sformatf("%4d",$signed(expected[j]))};
        return s;
    endfunction

    function void do_copy(uvm_object rhs);
        npu_seq_item rhs_;
        super.do_copy(rhs);
        void'($cast(rhs_, rhs));
        W=rhs_.W; A=rhs_.A; scale=rhs_.scale;
        wgt_addr=rhs_.wgt_addr; act_addr=rhs_.act_addr; out_addr=rhs_.out_addr;
        actual_out=rhs_.actual_out; expected=rhs_.expected;
    endfunction
endclass
`endif
