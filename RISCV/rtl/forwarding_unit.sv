// =============================================================================
// forwarding_unit.sv — Data Forwarding for the Pipeline
// =============================================================================
// Detects EX-EX and MEM-EX data hazards and selects the bypass source.
//
//  forward_a / forward_b encoding:
//    00  No forwarding — use ID/EX register file output
//    01  MEM-WB forward — use result latched after MEM stage
//    10  EX-MEM forward — use ALU result from previous EX stage
//
// Priority: EX-MEM hazard takes precedence over MEM-WB hazard
//   (EX-MEM value is newer; MEM-WB may be from two instructions back)
//
// Note: loads forwarded from MEM-WB (load-use stall ensures data is ready).
//       The HDU inserts one stall cycle so the forwarding path is valid.
// =============================================================================

`timescale 1ns/1ps

module forwarding_unit (
    // EX stage source registers
    input  logic [4:0] ex_rs1,
    input  logic [4:0] ex_rs2,

    // EX/MEM pipeline register
    input  logic       exmem_reg_write,
    input  logic [4:0] exmem_rd,

    // MEM/WB pipeline register
    input  logic       memwb_reg_write,
    input  logic [4:0] memwb_rd,

    // Forwarding select signals
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);
    // Forward A
    always_comb begin
        if (exmem_reg_write && exmem_rd != 5'b0 && exmem_rd == ex_rs1)
            forward_a = 2'b10;   // EX-MEM forward
        else if (memwb_reg_write && memwb_rd != 5'b0 && memwb_rd == ex_rs1)
            forward_a = 2'b01;   // MEM-WB forward
        else
            forward_a = 2'b00;   // no forward
    end

    // Forward B
    always_comb begin
        if (exmem_reg_write && exmem_rd != 5'b0 && exmem_rd == ex_rs2)
            forward_b = 2'b10;
        else if (memwb_reg_write && memwb_rd != 5'b0 && memwb_rd == ex_rs2)
            forward_b = 2'b01;
        else
            forward_b = 2'b00;
        end

endmodule
