// =============================================================================
// branch_predictor.sv — 2-bit Saturating Counter Branch Predictor
// =============================================================================
// Direct-mapped table: ENTRIES entries indexed by PC[ENTRY_W+1:2].
// Each entry holds a 2-bit saturating counter:
//   11 Strongly Taken
//   10 Weakly Taken     → predict TAKEN when counter[1] == 1
//   01 Weakly Not-Taken
//   00 Strongly Not-Taken
//
// Why EX-stage resolution instead of MEM:
//   MEM-stage resolution created a conflict between the synchronous load-use
//   stall (HDU freezes IF/ID for 1 cycle) and the asynchronous branch flush
//   (always_comb clears ID/EX in the same cycle).  When both fired together,
//   the pipeline register update order was inconsistent → wrong instructions
//   proceeded past ID.  Moving resolution to EX separates the two mechanisms
//   in time and reduces the branch penalty from 3 cycles to 1 cycle.
//
// Loop accuracy: ~90% (inner loops re-enter the Strongly Taken state after
//   the first iteration; the single miss is only on loop exit).
// =============================================================================

`timescale 1ns/1ps

module branch_predictor #(
    parameter ENTRIES  = 64,
    parameter ENTRY_W  = $clog2(ENTRIES)   // index width = 6
)(
    input  logic        clk,
    input  logic        rst_n,

    // Prediction request (IF stage)
    input  logic [31:0] pc_fetch,
    output logic        predict_taken,
    output logic [31:0] predict_target,   // PC+imm pre-computed by caller

    // Prediction target update (ID stage — after decode)
    input  logic        update_target_en,
    input  logic [31:0] update_pc,
    input  logic [31:0] update_target,

    // Outcome update (EX stage — after actual branch resolution)
    input  logic        update_en,
    input  logic [31:0] resolved_pc,
    input  logic        actual_taken
);
    // ── Prediction table ─────────────────────────────────────
    logic [1:0]  counter [ENTRIES-1:0];
    logic [31:0] target  [ENTRIES-1:0];

    logic [ENTRY_W-1:0] fetch_idx;
    logic [ENTRY_W-1:0] update_idx;
    logic [ENTRY_W-1:0] target_idx;

    assign fetch_idx  = pc_fetch   [ENTRY_W+1:2];
    assign update_idx = resolved_pc[ENTRY_W+1:2];
    assign target_idx = update_pc  [ENTRY_W+1:2];

    // Predict taken when MSB of counter is 1
    assign predict_taken  = counter[fetch_idx][1];
    assign predict_target = target[fetch_idx];

    // ── Counter update (EX outcome) ──────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < ENTRIES; i++)
                counter[i] <= 2'b01;   // init: Weakly Not-Taken
        end else if (update_en) begin
            if (actual_taken)
                counter[update_idx] <= (counter[update_idx] == 2'b11)
                                       ? 2'b11
                                       : counter[update_idx] + 1;
            else
                counter[update_idx] <= (counter[update_idx] == 2'b00)
                                       ? 2'b00
                                       : counter[update_idx] - 1;
        end
    end

    // ── Target update (ID — after imm decode) ────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < ENTRIES; i++)
                target[i] <= 32'b0;
        end else if (update_target_en) begin
            target[target_idx] <= update_target;
        end
    end

endmodule
