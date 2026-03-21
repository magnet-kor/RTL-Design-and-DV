// =============================================================================
// npu_sequences.sv  —  UVM 테스트 시퀀스 3종
//
// [npu_identity_seq]
//   W=I(단위행렬), A=[1..8], scale=0 → 기대: C[j]=A[j]
//   목적: weight 로딩, PS 수직 누적, 출력 정렬 SR 전체 경로 검증
//   버그 탐지력이 가장 높음: 부분 실패가 즉시 수치로 드러남
//
// [npu_random_seq (20회)]
//   rand W, A, scale(7~10) → INT8 곱셈기, 부호 확장, 클램프 무작위 탐색
//
// [npu_stress_seq (4 케이스)]
//   케이스1: all-max (W=127, A=127, scale=7) → Σ=129,032 → >>>7=1,008 → 클램프→127
//   케이스2: all-min (W=-128, A=-128, scale=7) → (-128)×(-128)×8=131,072 → 클램프→127
//   케이스3: A<0, W>0 → Σ<0 → ReLU → 0
//   케이스4: W=0 → Σ=0 → C=0
// =============================================================================
`ifndef NPU_SEQUENCES_SV
`define NPU_SEQUENCES_SV

class npu_base_seq extends uvm_sequence #(npu_seq_item);
    `uvm_object_utils(npu_base_seq)
    localparam int SA = 8;
    int unsigned num_txns = 1;
    function new(string name="npu_base_seq"); super.new(name); endfunction
    task automatic send_item(npu_seq_item item);
        start_item(item); finish_item(item);
    endtask
endclass

class npu_identity_seq extends npu_base_seq;
    `uvm_object_utils(npu_identity_seq)
    function new(string name="npu_identity_seq"); super.new(name); endfunction
    task body();
        npu_seq_item item;
        for (int t=0;t<num_txns;t++) begin
            item = npu_seq_item::type_id::create($sformatf("id_item_%0d",t));
            for (int k=0;k<SA;k++)
                for (int j=0;j<SA;j++)
                    item.W[k*SA+j] = (k==j) ? 8'sd1 : 8'sd0;  // Identity matrix
            for (int k=0;k<SA;k++) item.A[k] = k+1;  // [1,2,3,4,5,6,7,8]
            item.scale = 5'd0;  // scale=0: shift 없음 → C=A 직접 확인
            `uvm_info("SEQ",$sformatf("identity txn #%0d",t),UVM_MEDIUM)
            send_item(item);
        end
    endtask
endclass

class npu_random_seq extends npu_base_seq;
    `uvm_object_utils(npu_random_seq)
    function new(string name="npu_random_seq"); super.new(name); num_txns=20; endfunction
    task body();
        npu_seq_item item;
        for (int t=0;t<num_txns;t++) begin
            item = npu_seq_item::type_id::create($sformatf("rnd_item_%0d",t));
            if (!item.randomize()) `uvm_fatal("SEQ","randomize() failed")
            `uvm_info("SEQ",$sformatf("random txn #%0d scale=%0d",t,item.scale),UVM_MEDIUM)
            send_item(item);
        end
    endtask
endclass

class npu_stress_seq extends npu_base_seq;
    `uvm_object_utils(npu_stress_seq)
    function new(string name="npu_stress_seq"); super.new(name); endfunction
    task body();
        npu_seq_item item;
        // 케이스1: all-max
        item = npu_seq_item::type_id::create("max_item");
        foreach(item.W[i]) item.W[i]=8'sd127;
        foreach(item.A[k]) item.A[k]=8'sd127;
        item.scale=5'd7;
        send_item(item);
        // 케이스2: all-min×all-min → 양수 누적 → 클램프
        item = npu_seq_item::type_id::create("minmin_item");
        foreach(item.W[i]) item.W[i]=-8'sd128;
        foreach(item.A[k]) item.A[k]=-8'sd128;
        item.scale=5'd7;
        send_item(item);
        // 케이스3: A<0, W>0 → ReLU 발동 → C=0
        item = npu_seq_item::type_id::create("relu_item");
        foreach(item.W[i]) item.W[i]=8'sd1;
        foreach(item.A[k]) item.A[k]=-8'sd50;
        item.scale=5'd7;
        send_item(item);
        // 케이스4: W=0 → C=0
        item = npu_seq_item::type_id::create("zero_w_item");
        foreach(item.W[i]) item.W[i]=8'sd0;
        foreach(item.A[k]) item.A[k]=8'sd127;
        item.scale=5'd7;
        send_item(item);
    endtask
endclass
`endif
