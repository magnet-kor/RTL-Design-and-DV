# Design Notes — RISC-V 5-Stage Pipeline CPU

---

## 1. Branch Resolution: EX Stage (not MEM)

### Problem

Initial implementation resolved branches in the MEM stage.
When a `load` was immediately followed by a `branch`, two control signals
conflicted in the same clock cycle:

```
load-use stall  → synchronous  (HDU: holds PC and IF/ID for 1 cycle)
branch flush    → combinatorial (always_comb: clears ID/EX immediately)
```

The EX stall signal froze IF/ID while the MEM flush simultaneously
overwrote ID/EX in the same edge — leaving the pipeline in an
inconsistent state that propagated wrong instructions into WB.

### Fix

Move branch resolution to EX stage.

```
Before (MEM):   IF → ID → EX → [MEM branch resolve] → WB
                penalty = 3 cycles; flush/stall collision possible

After  (EX):    IF → ID → [EX branch resolve] → MEM → WB
                penalty = 1 cycle; flush/stall separated by one stage
```

### Quantitative impact

```
Branch frequency in test suite: ~20%
Penalty reduction:              3 cycles → 1 cycle (-2 cycles/branch)
CPI contribution:               0.20 × 2 = 0.40 cycles saved
CPI without predictor:          1.71  (measured)
CPI with 2-bit predictor:       ~1.45 (inner loops: 90% accuracy)
```

---

## 2. Forwarding Unit: Priority Ordering

Two forwarding paths are implemented:

```
EX-MEM  (10): ALU result from one instruction back  → freshest value
MEM-WB  (01): result from two instructions back     → may be load result
```

EX-MEM takes priority over MEM-WB because it is the more recent value.
When both EX-MEM and MEM-WB would match (two back-to-back writes to the
same register), the EX-MEM value is architecturally correct.

The forwarding unit does not forward from x0 (hardwired zero);
the `!= 5'b0` guard prevents false matches.

---

## 3. Load-Use Hazard: 1-Cycle Stall

A load followed immediately by a dependent instruction cannot be resolved
by forwarding — the memory read result does not exist until after EX stage
of the load, one cycle too late.

```
HDU action:
  pc_write     = 0  → freeze PC
  ifid_write   = 0  → freeze IF/ID
  idex_flush   = 1  → insert NOP bubble into ID/EX
```

Result: the dependent instruction executes one cycle later,
by which time the MEM-WB forwarding path delivers the loaded value.

Frequency in the test suite: ~8% of instructions are load-use pairs.
CPI penalty:  0.08 × 1 = 0.08 cycles.

---

## 4. 2-Bit Saturating Counter Branch Predictor

64-entry direct-mapped table, indexed by PC[7:2].

```
State machine per entry:
  11 Strongly Taken     ─┐
  10 Weakly Taken       ─┤→ predict TAKEN   (MSB = 1)
  01 Weakly Not-Taken   ─┤→ predict NOT-TAKEN (MSB = 0)
  00 Strongly Not-Taken ─┘

Initialised to Weakly Not-Taken (01).
```

Why 2-bit instead of 1-bit:
A 1-bit predictor flips state on every misprediction; it misses twice on
every loop exit (miss on exit + first entry of next execution).
A 2-bit predictor absorbs a single misprediction without changing the
prediction — a loop mispredicts only once per invocation (on exit).

Loop accuracy: ~90%
(one miss on loop exit; all subsequent iterations stay Strongly Taken)

---

## 5. Register File: Write-First Forwarding

When the WB stage writes and the ID stage reads the same register in the
same clock cycle, the read must return the new value.
Without this, the instruction in ID would see a stale value and the
forwarding unit would need an extra MEM-WB → ID bypass.

Implementation: combinatorial bypass in the read logic.

```systemverilog
assign rd1 = (ra1 == 5'b0)                  ? 32'b0 :
             (we && wa == ra1 && wa != 5'b0) ? wd    :
                                               regs[ra1];
```

---

## 6. Performance Summary

| Metric | Single-cycle | Pipeline |
|--------|-------------|---------|
| CPI | 1.00 | 1.71 |
| Max clock | ~1.0 GHz | ~2.7 GHz |
| Throughput | 1.0 GIPS | **1.58 GIPS** |
| Gate count | baseline | +73% |
| Flip-flops | baseline | +1,900% |

```
Throughput ratio = (1/1.71) × 2.7 = 1.58×

Critical path: ~370 ps
  → dominated by: regfile read → forwarding mux → ALU → branch condition
  → estimated using FA-chain delay from foundry Liberty characterisation
```

---

## 7. Instruction Coverage

| Type | Instructions | Notes |
|------|-------------|-------|
| R | ADD SUB AND OR XOR SLL SRL SRA SLT SLTU | All funct3/funct7 variants |
| I | ADDI ANDI ORI XORI SLTI SLTIU SLLI SRLI SRAI | Immediate arithmetic |
| Load | LB LH LW LBU LHU | Sign/zero extension in MEM stage |
| Store | SB SH SW | Sub-word write via byte enables |
| Branch | BEQ BNE BLT BGE BLTU BGEU | EX-stage resolution |
| Jump | JAL JALR | PC+4 linked to rd |
| Upper | LUI AUIPC | Pass-through ALU path |
