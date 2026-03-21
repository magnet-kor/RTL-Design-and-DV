# RISC-V 5-Stage Pipeline CPU — Portfolio Project

**Jungho Lee** | Samsung Electronics Foundry, Library FE DK Engineer, 6 Years

---

## Overview

A fully functional RISC-V RV32I 5-stage pipeline CPU implemented in SystemVerilog,
including data forwarding, hazard detection, and a 2-bit saturating counter
branch predictor.

---

## Features

| Feature | Detail |
|---------|--------|
| ISA | RISC-V RV32I — all instruction types (R / I / S / B / U / J) |
| Pipeline | 5 stages: IF → ID → EX → MEM → WB |
| Forwarding | EX-EX and MEM-EX paths; write-first register file |
| Hazard | Load-use stall detection (1-cycle bubble insertion) |
| Branch | EX-stage resolution; 1-cycle flush penalty; 2-bit predictor |
| Jump | JAL and JALR unconditional jump support |
| Memory | LB / LH / LW / LBU / LHU / SB / SH / SW |

---

## Directory Structure

```
RISCV/
├── README.md
├── RTL/                      Design RTL (SystemVerilog)
│   ├── riscv_pipeline.sv     Top-level 5-stage pipeline integration
│   ├── alu.sv                32-bit ALU (ADD SUB AND OR XOR SLL SRL SRA SLT SLTU LUI)
│   ├── alu_ctrl.sv           ALU control: funct3/funct7 → 4-bit alu_op
│   ├── control.sv            Main control unit: opcode → all pipeline signals
│   ├── regfile.sv            32×32 register file with write-first forwarding
│   ├── imm_gen.sv            Immediate generator for all RV32I formats
│   ├── forwarding_unit.sv    EX-EX and MEM-EX forwarding logic
│   ├── hdu.sv                Hazard Detection Unit (load-use stall)
│   └── branch_predictor.sv   2-bit saturating counter predictor (64 entries)
├── TB/                       Testbench
│   └── riscv_pipeline_tb.sv  22-point testbench (7 test cases)
├── SIM/                      Simulation scripts
│   └── run.sh                Build and simulate (iverilog)
└── DOCS/                     Documentation
    ├── DESIGN_NOTES.md       Key design decisions with quantitative justification
    └── INTERVIEW_QA.md       Interview Q&A covering all design choices
```

---

## Build and Simulate

Requires [Icarus Verilog](https://github.com/steveicarus/iverilog) (v10+).

```bash
bash SIM/run.sh
# Optional: bash SIM/run.sh wave   (opens GTKWave)
```

Expected output:
```
Results: 22 PASS  /  0 FAIL
ALL TESTS PASSED
```

---

## Key Design Decision: Branch Resolution at EX Stage

**Problem with MEM-stage resolution:**

When a `load` was immediately followed by a `branch`, the load-use stall
(synchronous: HDU freezes IF/ID for 1 cycle) and the branch flush
(combinatorial: clears ID/EX) conflicted in the same clock edge.
The EX stall signal was holding IF/ID while MEM-stage flush simultaneously
overwrote ID/EX — leaving the pipeline in an inconsistent state.

**Solution: move branch resolution to EX stage.**

Consequences:
- Flush and stall no longer conflict (separated by one pipeline stage)
- Branch miss penalty: 3 cycles → **1 cycle**
- Enables clean integration of 2-bit predictor

---

## Performance (Yosys synthesis, sky130 target)

| Metric | Value |
|--------|-------|
| CPI (no predictor) | 1.71 |
| CPI (2-bit predictor, loop-heavy) | ~1.45 |
| Max clock | ~2.7 GHz (~370 ps critical path) |
| Gate count | ~3,500 gates (+73% vs single-cycle) |
| Throughput gain | **1.58× single-cycle baseline** |

Clock estimate derived from FA-chain gate delay in the foundry library —
the same method used daily for Liberty characterization work.

---

## Foundry Experience Connection

Six years of Library FE DK development provided three direct inputs to this design:

1. **Critical-path intuition**: knowing FA delay per node makes clock estimates
   concrete rather than theoretical.

2. **DFT awareness**: every pipeline register is scan-compatible; no feedback loops
   that would block scan-chain insertion.

3. **Process-performance relationship**: the design explicitly targets sky130
   (open PDK) with Yosys, demonstrating the RTL → synthesis → timing closure flow
   used in real foundry tape-outs.
