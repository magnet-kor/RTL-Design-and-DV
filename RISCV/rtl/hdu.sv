// =============================================================================
// hdu.sv — Hazard Detection Unit (Load-Use Stall)
// =============================================================================
// Detects load-use hazard: a LOAD in ID/EX whose destination matches a source
// register needed by the instruction currently in IF/ID.
//
// Action: assert stall for 1 cycle
//   - pc_write   = 0  → freeze PC
//   - if_id_write = 0  → freeze IF/ID register
//   - id_ex_flush = 1  → insert NOP bubble into ID/EX
//
// Interaction with branch flush (resolved at EX):
//   Branch flush is driven by a separate always_comb in the pipeline top-level.
//   Separating load-use stall (synchronous) from branch flush (combinatorial)
//   avoids the race condition that existed when branches were resolved at MEM:
//   both signals would assert in the same clock edge causing conflicting
//   updates to the same pipeline registers.
// =============================================================================

`timescale 1ns/1ps

module hdu (
    // ID/EX pipeline register contents
    input  logic       idex_mem_read,  // load instruction in EX stage
    input  logic [4:0] idex_rd,        // destination register of load

    // IF/ID instruction source registers
    input  logic [4:0] ifid_rs1,
    input  logic [4:0] ifid_rs2,

    // Stall outputs
    output logic       stall           // 1 = insert bubble this cycle
);
    assign stall = idex_mem_read
                && ((idex_rd == ifid_rs1 && ifid_rs1 != 5'b0)
                 || (idex_rd == ifid_rs2 && ifid_rs2 != 5'b0));

endmodule
