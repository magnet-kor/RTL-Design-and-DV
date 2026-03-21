// =============================================================================
// riscv_pipeline_tb.sv — Testbench for RISC-V 5-Stage Pipeline CPU
// =============================================================================
// Test cases:
//   TC1: R-type arithmetic   (ADD SUB AND OR XOR SLL SRL SLT)
//   TC2: I-type immediate    (ADDI ANDI ORI XORI SLTI)
//   TC3: Load/Store + load-use hazard
//   TC4: Branch taken / not-taken (BEQ BNE)
//   TC5: Forwarding chain (3 back-to-back dependent instructions)
//   TC6: Loop — sum 1..10 (warms branch predictor)
//   TC7: JAL unconditional jump
// =============================================================================

`timescale 1ns/1ps

module riscv_pipeline_tb;

    logic clk = 0;
    logic rst_n;
    always #5 clk = ~clk;

    riscv_pipeline dut (.clk(clk), .rst_n(rst_n));

    integer pass_cnt;
    integer fail_cnt;

    // ── Register read helper ──────────────────────────────────
    `define XREG(n) dut.u_rf.regs[n]

    // ── Instruction encoding ──────────────────────────────────
    // R-type
    function [31:0] R(input [6:0] f7, input [4:0] rs2, rs1, input [2:0] f3, input [4:0] rd, input [6:0] op);
        R = {f7, rs2, rs1, f3, rd, op};
    endfunction
    // I-type
    function [31:0] I(input [11:0] imm, input [4:0] rs1, input [2:0] f3, input [4:0] rd, input [6:0] op);
        I = {imm, rs1, f3, rd, op};
    endfunction
    // S-type
    function [31:0] S(input [11:0] imm, input [4:0] rs2, rs1, input [2:0] f3);
        S = {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011};
    endfunction
    // B-type (imm is the byte offset, bit[0] ignored)
    function [31:0] B(input [12:0] imm, input [4:0] rs1, rs2, input [2:0] f3);
        B = {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], 7'b1100011};
    endfunction
    // J-type
    function [31:0] J(input [20:0] imm, input [4:0] rd);
        J = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    endfunction
    // U-type
    function [31:0] U(input [19:0] imm20, input [4:0] rd, input [6:0] op);
        U = {imm20, rd, op};
    endfunction

    localparam NOP     = 32'h0000_0013;
    localparam OP      = 7'b0110011;
    localparam OP_IMM  = 7'b0010011;
    localparam LOAD    = 7'b0000011;
    localparam LUI_OP  = 7'b0110111;

    // ── Check helper ─────────────────────────────────────────
    task check_eq;
        input [63:0] tag; // not used, printed inline
        input [31:0] got, exp;
        input [8*40:1] label;
        begin
            if (got === exp) begin
                $display("  PASS  %0s  got=0x%08x", label, got);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  %0s  got=0x%08x  exp=0x%08x", label, got, exp);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ── Load program into imem ────────────────────────────────
    integer ii;
    task load_prog_8;
        input [31:0] i0,i1,i2,i3,i4,i5,i6,i7;
        begin
            dut.imem[0]=i0; dut.imem[1]=i1; dut.imem[2]=i2; dut.imem[3]=i3;
            dut.imem[4]=i4; dut.imem[5]=i5; dut.imem[6]=i6; dut.imem[7]=i7;
            for (ii=8; ii<1024; ii=ii+1) dut.imem[ii]=NOP;
        end
    endtask

    task load_prog_12;
        input [31:0] i0,i1,i2,i3,i4,i5,i6,i7,i8,i9,i10,i11;
        begin
            dut.imem[0]=i0; dut.imem[1]=i1;  dut.imem[2]=i2;  dut.imem[3]=i3;
            dut.imem[4]=i4; dut.imem[5]=i5;  dut.imem[6]=i6;  dut.imem[7]=i7;
            dut.imem[8]=i8; dut.imem[9]=i9;  dut.imem[10]=i10;dut.imem[11]=i11;
            for (ii=12; ii<1024; ii=ii+1) dut.imem[ii]=NOP;
        end
    endtask

    task do_reset;
        begin
            rst_n = 0;
            repeat(3) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    // =========================================================================
    // Main test flow
    // =========================================================================
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        // ── TC1: R-type arithmetic ────────────────────────────
        $display("\n=== TC1: R-type arithmetic ===");
        // x1=10  x2=3
        // x3=ADD=13  x4=SUB=7  x5=AND=2  x6=OR=11  x7=XOR=9  x8=SLL=80  x9=SRL=1
        load_prog_8(
            I(12'd10, 5'd0, 3'b000, 5'd1, OP_IMM),            // ADDI x1,x0,10
            I(12'd3,  5'd0, 3'b000, 5'd2, OP_IMM),            // ADDI x2,x0,3
            R(7'h00, 5'd2, 5'd1, 3'b000, 5'd3, OP),           // ADD  x3=13
            R(7'h20, 5'd2, 5'd1, 3'b000, 5'd4, OP),           // SUB  x4=7
            R(7'h00, 5'd2, 5'd1, 3'b111, 5'd5, OP),           // AND  x5=2
            R(7'h00, 5'd2, 5'd1, 3'b110, 5'd6, OP),           // OR   x6=11
            R(7'h00, 5'd2, 5'd1, 3'b100, 5'd7, OP),           // XOR  x7=9
            R(7'h00, 5'd2, 5'd1, 3'b001, 5'd8, OP)            // SLL  x8=80
        );
        do_reset;
        repeat(20) @(posedge clk); #1;
        check_eq(0, `XREG(3), 32'd13,  "ADD x1+x2=13      ");
        check_eq(0, `XREG(4), 32'd7,   "SUB x1-x2=7       ");
        check_eq(0, `XREG(5), 32'd2,   "AND x1&x2=2       ");
        check_eq(0, `XREG(6), 32'd11,  "OR  x1|x2=11      ");
        check_eq(0, `XREG(7), 32'd9,   "XOR x1^x2=9       ");
        check_eq(0, `XREG(8), 32'd80,  "SLL x1<<x2=80     ");

        // ── TC2: I-type immediate ─────────────────────────────
        $display("\n=== TC2: I-type immediate ===");
        load_prog_8(
            I(12'd100, 5'd0, 3'b000, 5'd1, OP_IMM),           // ADDI x1=100
            I(12'd7,   5'd0, 3'b000, 5'd2, OP_IMM),           // ADDI x2=7
            I(12'd3,   5'd1, 3'b111, 5'd3, OP_IMM),           // ANDI x3=x1&3 = 100&3=0
            I(12'd5,   5'd2, 3'b110, 5'd4, OP_IMM),           // ORI  x4=x2|5 = 7|5=7
            I(12'd50,  5'd1, 3'b010, 5'd5, OP_IMM),           // SLTI x5 = (100<50)=0
            I(12'd200, 5'd1, 3'b010, 5'd6, OP_IMM),           // SLTI x6 = (100<200)=1
            NOP, NOP
        );
        do_reset;
        repeat(20) @(posedge clk); #1;
        check_eq(0, `XREG(3), 32'd0,  "ANDI 100&3=0      ");
        check_eq(0, `XREG(4), 32'd7,  "ORI  7|5=7        ");
        check_eq(0, `XREG(5), 32'd0,  "SLTI 100<50=0     ");
        check_eq(0, `XREG(6), 32'd1,  "SLTI 100<200=1    ");

        // ── TC3: Load/Store + load-use hazard ─────────────────
        $display("\n=== TC3: Load/Store + Load-Use Hazard ===");
        // SW 42 at addr 0  → LW x3 from addr 0  → ADD x4=x3+x3 (hazard!)
        load_prog_8(
            I(12'd42,  5'd0, 3'b000, 5'd1, OP_IMM),           // x1 = 42
            S(12'd0,   5'd1, 5'd0,   3'b010),                  // SW x1, 0(x0)
            NOP,
            I(12'd0,   5'd0, 3'b010, 5'd3, LOAD),             // LW x3, 0(x0)
            R(7'h00,   5'd3, 5'd3,   3'b000, 5'd4, OP),       // ADD x4=x3+x3 [load-use]
            NOP, NOP, NOP
        );
        do_reset;
        repeat(20) @(posedge clk); #1;
        check_eq(0, `XREG(3), 32'd42,  "LW  x3=42         ");
        check_eq(0, `XREG(4), 32'd84,  "LU  x4=x3+x3=84   ");

        // ── TC4: Branch taken / not-taken ─────────────────────
        $display("\n=== TC4: Branch ===");
        // x1=5 x2=5: BEQ taken → skip x3=99 → x4=x3+1=1
        // x5=3 x6=7: BNE taken → skip x7=99
        load_prog_12(
            I(12'd5,  5'd0, 3'b000, 5'd1, OP_IMM),            // PC=0: x1=5
            I(12'd5,  5'd0, 3'b000, 5'd2, OP_IMM),            // PC=4: x2=5
            B(13'd8,  5'd1, 5'd2,   3'b000),                   // PC=8: BEQ x1,x2 → +8=PC16
            I(12'd99, 5'd0, 3'b000, 5'd3, OP_IMM),            // PC=12: x3=99 [SKIP]
            I(12'd1,  5'd3, 3'b000, 5'd4, OP_IMM),            // PC=16: x4=x3+1=1
            I(12'd3,  5'd0, 3'b000, 5'd5, OP_IMM),            // PC=20: x5=3
            I(12'd7,  5'd0, 3'b000, 5'd6, OP_IMM),            // PC=24: x6=7
            B(13'd8,  5'd5, 5'd6,   3'b001),                   // PC=28: BNE x5,x6 → +8=PC36
            I(12'd99, 5'd0, 3'b000, 5'd7, OP_IMM),            // PC=32: x7=99 [SKIP]
            NOP,                                                // PC=36
            NOP, NOP
        );
        do_reset;
        repeat(30) @(posedge clk); #1;
        check_eq(0, `XREG(3), 32'd0,  "BEQ taken x3=0    ");
        check_eq(0, `XREG(4), 32'd1,  "BEQ taken x4=1    ");
        check_eq(0, `XREG(7), 32'd0,  "BNE taken x7=0    ");

        // ── TC5: EX-EX forwarding chain ───────────────────────
        $display("\n=== TC5: Forwarding chain ===");
        // x1=4: x2=x1+1=5, x3=x2+1=6, x4=x3+1=7 (3 back-to-back deps)
        load_prog_8(
            I(12'd4,  5'd0, 3'b000, 5'd1, OP_IMM),            // x1=4
            I(12'd1,  5'd1, 3'b000, 5'd2, OP_IMM),            // x2=x1+1=5 [EX-EX fwd]
            I(12'd1,  5'd2, 3'b000, 5'd3, OP_IMM),            // x3=x2+1=6 [EX-EX fwd]
            I(12'd1,  5'd3, 3'b000, 5'd4, OP_IMM),            // x4=x3+1=7 [EX-EX fwd]
            NOP, NOP, NOP, NOP
        );
        do_reset;
        repeat(15) @(posedge clk); #1;
        check_eq(0, `XREG(2), 32'd5,  "FWD chain x2=5    ");
        check_eq(0, `XREG(3), 32'd6,  "FWD chain x3=6    ");
        check_eq(0, `XREG(4), 32'd7,  "FWD chain x4=7    ");

        // ── TC6: Loop sum 1..10 ───────────────────────────────
        $display("\n=== TC6: Loop sum 1..10 ===");
        // x1=sum=0, x2=i=1, x3=10
        // loop: x1+=x2; x2++; if x2<=x3 goto loop → x1=55
        // PC: 0=x1=0, 4=x2=1, 8=x3=10,
        //     12=ADD(loop), 16=ADDI x2++, 20=BGE x3,x2 → -8 (PC=12)
        // BGE imm = -8 = 13'b1_111111_11000
        load_prog_8(
            I(12'd0,  5'd0, 3'b000, 5'd1, OP_IMM),            // x1=0
            I(12'd1,  5'd0, 3'b000, 5'd2, OP_IMM),            // x2=1
            I(12'd10, 5'd0, 3'b000, 5'd3, OP_IMM),            // x3=10
            R(7'h00, 5'd2, 5'd1, 3'b000, 5'd1, OP),           // x1+=x2
            I(12'd1,  5'd2, 3'b000, 5'd2, OP_IMM),            // x2++
            B(13'h1FF8, 5'd3, 5'd2, 3'b101),        // BGE x3,x2,-8
            NOP, NOP
        );
        do_reset;
        repeat(90) @(posedge clk); #1;
        check_eq(0, `XREG(1), 32'd55, "Loop sum=55       ");

        // ── TC7: JAL ─────────────────────────────────────────
        $display("\n=== TC7: JAL ===");
        // PC=0: x5=7; PC=4: JAL x1,+8 → jump to PC=12, x1=8
        // PC=8: x6=99 [skipped]; PC=12: x7=x5 (=7)
        load_prog_8(
            I(12'd7,  5'd0, 3'b000, 5'd5, OP_IMM),            // PC=0: x5=7
            J(21'd8,  5'd1),                                   // PC=4: JAL x1,+8 → PC=12
            I(12'd99, 5'd0, 3'b000, 5'd6, OP_IMM),            // PC=8: x6=99 [SKIP]
            I(12'd0,  5'd5, 3'b000, 5'd7, OP_IMM),            // PC=12: x7=x5=7
            NOP, NOP, NOP, NOP
        );
        do_reset;
        repeat(20) @(posedge clk); #1;
        check_eq(0, `XREG(1), 32'd8,  "JAL link x1=8     ");
        check_eq(0, `XREG(6), 32'd0,  "JAL skip  x6=0    ");
        check_eq(0, `XREG(7), 32'd7,  "JAL dest  x7=7    ");

        // ── Summary ──────────────────────────────────────────
        $display("\n============================================");
        $display("  Results: %0d PASS  /  %0d FAIL", pass_cnt, fail_cnt);
        $display("============================================");
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  FAILURES DETECTED");
        $finish;
    end

    initial begin
        #100000; $display("TIMEOUT"); $finish;
    end

endmodule
