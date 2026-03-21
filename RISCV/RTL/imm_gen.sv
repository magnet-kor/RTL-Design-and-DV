// =============================================================================
// imm_gen.sv — Immediate Generator for RV32I
// =============================================================================
`timescale 1ns/1ps

module imm_gen (
    input  logic [31:0] instr,
    output logic [31:0] imm
);
    // Pre-extract fields as wires (iverilog part-select in always workaround)
    wire        sign  = instr[31];
    wire [11:0] i_imm = instr[31:20];
    wire [4:0]  i_lo  = instr[11:7];
    wire [6:0]  s_hi  = instr[31:25];
    wire [7:0]  u_hi8 = instr[19:12];
    wire [9:0]  j_mid = instr[30:21];
    wire [5:0]  b_hi6 = instr[30:25];
    wire [3:0]  b_lo4 = instr[11:8];
    wire [19:0] u_imm = instr[31:12];
    wire [6:0]  opc   = instr[6:0];

    wire [31:0] imm_i = {{20{sign}}, i_imm};
    wire [31:0] imm_s = {{20{sign}}, s_hi, i_lo};
    wire [31:0] imm_b = {{19{sign}}, sign, instr[7], b_hi6, b_lo4, 1'b0};
    wire [31:0] imm_u = {u_imm, 12'b0};
    wire [31:0] imm_j = {{11{sign}}, sign, u_hi8, instr[20], j_mid, 1'b0};

    always_comb begin
        case (opc)
            7'b0000011, 7'b0010011,
            7'b1100111, 7'b1110011: imm = imm_i;
            7'b0100011:             imm = imm_s;
            7'b1100011:             imm = imm_b;
            7'b0110111, 7'b0010111: imm = imm_u;
            7'b1101111:             imm = imm_j;
            default:                imm = 32'b0;
        endcase
    end
endmodule
