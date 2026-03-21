# RTL Design & Verification Portfolio

**Author:** Jungho Lee — Samsung Electronics Foundry, Library FE DK Engineer, 6 years
**Stack:** SystemVerilog RTL · UVM · Yosys (sky130) · Verilator · Python

---

## Repository Structure

```
RTL-Design-and-DV/
├── NPU/          Weight Stationary NPU — RTL + UVM Verification
└── ACCEL/        LLM Accelerator — Systolic Array → Transformer Decoder
```

---

## Projects

### NPU — Weight Stationary NPU with UVM Testbench

8×8 Weight Stationary Systolic Array NPU with full UVM verification environment.

| Item | Detail |
|------|--------|
| Architecture | 8×8 WS Systolic Array (64 PE) |
| Interface | APB Slave (CPU config) · AXI4 Master (DRAM DMA) |
| Post-processing | ReLU + INT8 quantization (scale + clamp) |
| Verification | UVM Agent/Env/Scoreboard/Coverage |
| Memory | 256 KB on-chip SRAM (weight buffer) |

→ [`NPU/`](./NPU/)

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

## Background

Six years at Samsung Electronics Foundry (Library FE DK & Verification):
SRAM compiler characterization, Liberty timing chain analysis, Fusion Compiler
RTL-to-netlist synthesis and STA, full DFT sign-off (JTAG / Logic BIST / Memory BIST / ATPG),
Palladium/Zebu emulation, and production RTL design of the DNA BIST controller for eFlash and eMRAM.

This portfolio translates that physical design intuition into AI accelerator RTL —
every metric has a derivation, every design decision has a quantified trade-off.
