# RTL Design & Verification Portfolio

**Author:** Jungho Lee — Samsung Electronics Foundry, Library FE DK Engineer, 6 years
**Stack:** SystemVerilog RTL · UVM · Yosys (sky130) · Verilator · Python

---

## Repository Structure

```
RTL-Design-and-DV/
├── NPU/          Weight Stationary NPU — RTL + UVM Verification
├── ACCEL/        LLM Accelerator — Systolic Array → Transformer Decoder
└── RISCV/        RISC-V RV32I 5-Stage Pipelined CPU
```

모든 프로젝트는 동일한 서브 디렉터리 규칙을 따릅니다:

| 디렉터리 | 내용 |
|----------|------|
| `RTL/`   | 합성 가능한 설계 RTL (SystemVerilog) |
| `TB/`    | 테스트벤치 |
| `UVM/`   | UVM 검증 환경 (해당 프로젝트) |
| `SIM/`   | 시뮬레이션 스크립트 / 출력 |
| `SYNTH/` | 합성 스크립트 (Yosys) |
| `GOLDEN/`| Python 비트 정확도 레퍼런스 모델 |
| `DOCS/`  | 설계 문서 |

---

## Projects

### NPU — Weight Stationary NPU with UVM Testbench

8×8 Weight Stationary Systolic Array NPU with full UVM verification environment.

| Item | Detail |
|------|--------|
| Architecture | 8×8 WS Systolic Array (64 PE) |
| Interface | APB Slave (CPU config) · AXI4 Master (DRAM DMA) |
| Post-processing | ReLU + INT8 quantization (scale + clamp) |
| Verification | UVM Agent / Env / Scoreboard / Coverage |
| Memory | 256 KB on-chip SRAM (weight buffer) |

→ [`NPU/`](./NPU/README.md)

---

### ACCEL — LLM Accelerator (Qwen 2.5-0.5B Decoder Layer)

Reuses the 8×8 Output Stationary Systolic Array 9× per decoder layer to run full Transformer inference in hardware.

| Item | Detail |
|------|--------|
| Target | Qwen 2.5-0.5B (hidden=896, GQA 14/2 heads, FFN=4864) |
| Dataflow | Output Stationary, batch=1 |
| Operators | RMSNorm · RoPE · QKV Proj · MHA · Softmax · FFN (SwiGLU) |
| Throughput | ~2.4 tok/s @ 200 MHz (sky130) |
| Synthesis | Yosys + ABC, sky130 PDK |

→ [`ACCEL/`](./ACCEL/DOCS/README.md)

---

### RISCV — 5-Stage Pipelined RISC-V CPU (RV32I)

Fully functional RV32I 5-stage pipeline with data forwarding, hazard detection, and 2-bit branch predictor.

| Item | Detail |
|------|--------|
| ISA | RISC-V RV32I (all instruction types: R/I/S/B/U/J) |
| Pipeline | IF → ID → EX → MEM → WB |
| Forwarding | EX-EX and MEM-EX paths; write-first register file |
| Branch | EX-stage resolution; 1-cycle flush; 2-bit saturating predictor |
| CPI | 1.71 (no predictor) / ~1.45 (2-bit, loop-heavy) |
| Synthesis | ~3,500 gates, sky130 target |

→ [`RISCV/`](./RISCV/README.md)

---

## Background

Six years at Samsung Electronics Foundry (Library FE DK & Verification):
SRAM compiler characterization, Liberty timing chain analysis, Fusion Compiler
RTL-to-netlist synthesis and STA, full DFT sign-off (JTAG / Logic BIST / Memory BIST / ATPG),
Palladium/Zebu emulation, and production RTL design of the DNA BIST controller for eFlash and eMRAM.

This portfolio translates that physical design intuition into AI accelerator RTL —
every metric has a derivation, every design decision has a quantified trade-off.
