# NPU → LLM Accelerator: 8×8 Systolic Array Reuse

**Target:** Qwen 2.5-0.5B Transformer Decoder Layer  
**Platform:** SystemVerilog RTL + Yosys (sky130 PDK, 200 MHz)  
**Author:** Jungho Lee — Samsung Electronics Foundry, Library FE DK Engineer, 6 years

> The 8×8 Output Stationary Systolic Array designed in Phase 2 for CNN inference
> is reused without modification 9× per decoder layer — for QKV projection,
> multi-head attention, and FFN. The same hardware runs both CNN and Transformer
> workloads. This is the direction of Tesla FSD Chip.

---

## Architecture Overview

```
Phase 2 — CNN NPU                     Phase 4 — LLM Decoder Layer
────────────────────────              ─────────────────────────────────
8×8 OS Systolic Array (64 PE)    →   Same array, 9× time-multiplexed
256 KB Scratchpad SRAM           →   + KV Cache (DRAM, AXI4 Write)
AXI4 DMA Engine (Read only)      →   + Bidirectional DMA (R+W)
Single-mode FSM                  →   + Dual-mode FSM (Prefill / Decode)
ReLU post-processor              →   + Softmax / RMSNorm / RoPE / SiLU
```

```
Decoder Layer Data Flow:

x_in[896] ──► RMSNorm ──► QKV Proj ──► RoPE ──► KV Cache (DRAM)
                              │                        │
                    [systolic ×3]              K_hist, V_hist
                                                       │
                              MHA ◄───────────────────┘
                    [systolic ×3]
                              │
                    Residual Add ──► RMSNorm ──► FFN ──► Residual Add ──► x_out
                                               [systolic ×3]
```

---

## Key Numbers

| Metric | Value | Derivation |
|--------|-------|------------|
| Systolic array reuse | **9× / layer** | QKV(3) + MHA(3) + FFN(3) |
| FFN MAC share | **87.7%** | 13.07M / 14.9M per decode step |
| Arithmetic intensity | **1.05 MAC/byte** | memory-bound; roofline knee = 8.0 |
| HW utilization | **13.1%** | 1.05 / 8.0 — DRAM bandwidth-limited |
| KV Cache size | **3.15 MB** | 512 × 128 × 2 × 24 layers → DRAM |
| QKV latency | **129,045 cycles** | 0.645 ms @ 200 MHz |
| Softmax latency | **18 cycles** | tree_max(3)+sub+exp+tree_sum(3)+recip(9)+mul |
| RMSNorm latency | **22 cycles** | 1+10+1+8+1+1 (6 stages, 1.55× vs LayerNorm) |
| RoPE LUT size | **16 KB** | 256×32×2×1B (INT8 Q7), 16× faster than CORDIC |
| 1 layer / token | **17.5 ms** | 3,490,000 cycles @ 200 MHz |
| Throughput | **2.4 tok/s** | 420 ms × 24 layers |
| Synthesis | **sky130, 200 MHz** | Yosys — see `phase4/synth/FINAL_SYNTH_REPORT.md` |

---

## Architecture Decision Log

| Decision | Alternative Considered | Rationale |
|----------|----------------------|-----------|
| Shared systolic array (9×) | 9 separate instances | Data dependency prevents parallel execution; 9× area saved |
| Output Stationary | Weight Stationary | batch=1 inference; same TPU v1 rationale; WS offers no reuse benefit |
| KV Cache in DRAM | On-chip SRAM | 3.15 MB >> 256 KB limit (12×) |
| RMSNorm over LayerNorm | LayerNorm | 22 vs 34 cycles (1.55×); no mean pass needed |
| EXP LUT (512 B, 1 cycle) | CORDIC | 1 vs 16 cycles; negligible area cost |
| SiLU LUT (256 B, 1 cycle) | EXP-based compute | 1 vs 8 cycles; same INT8 accuracy (±0.4%) |
| RoPE precomputed LUT | On-the-fly CORDIC | 16× faster; 16 KB fits in SRAM budget |
| `>>3` for ÷√64 | Divider circuit | head_dim=64; √64=8=2³; zero latency |
| Reciprocal LUT in ISQRT | `/` operator | Yosys synthesizes `/` as iterative divider → timing failure |
| recip_nr 2-stage pipeline | 1-stage per iteration | 64-bit multiply exceeded 5 ns; adds 4 cycles (0.0016% of layer) |
| x_in FF latch (7 KB) | SRAM offload | Simplicity; offload to SRAM saves 60% decoder area (future work) |

---

## Repository Structure

```
npu-design/
├── README.md
├── phase2/
│   └── sv/
│       ├── pe.sv              Processing Element (Output Stationary MAC)
│       └── systolic_array.sv  8×8 Array — reused without modification in Phase 4
└── phase4/
    ├── golden/                Python bit-accurate models
    │   ├── model_analysis.py  FLOP / arithmetic intensity analysis
    │   ├── kv_cache_analysis.py  KV memory sizing and DMA overhead
    │   ├── softmax_golden.py  Fixed-point softmax reference
    │   └── rmsnorm_rope_golden.py  RMSNorm and RoPE reference
    ├── sv/                    RTL modules
    │   ├── decoder_layer.sv   Top — 13-state dual-mode FSM
    │   ├── mha.sv             GQA attention (QKᵀ + softmax + AV + OutProj)
    │   ├── ffn.sv             SwiGLU FFN (FC1 + SiLU/gate + FC2 + FC3)
    │   ├── qkv_proj.sv        QKV projection (tiled systolic)
    │   ├── rope.sv            Rotary position embedding (LUT-based)
    │   ├── rmsnorm.sv         RMS normalization (6-stage pipeline)
    │   ├── kv_cache.sv        KV write-before-read FSM
    │   ├── dma_engine_v2.sv   AXI4 bidirectional DMA
    │   ├── softmax.sv         Safe softmax pipeline
    │   ├── tree_max.sv        Binary tree MAX reduction
    │   ├── tree_sum.sv        Binary tree SUM reduction
    │   ├── exp_lut.sv         EXP look-up table (512 B)
    │   ├── recip_nr.sv        Newton-Raphson reciprocal (9 cycles)
    │   └── silu_lut.sv        SiLU look-up table (256 B)
    ├── tb/                    LUT generation scripts
    │   ├── gen_exp_lut.py
    │   ├── gen_silu_lut.py
    │   └── gen_rope_lut.py
    ├── synth/                 Yosys synthesis
    │   ├── synth_decoder.ys
    │   ├── synth_abc.sdc
    │   └── FINAL_SYNTH_REPORT.md
    └── docs/
        ├── ARCH_SPEC.md
        └── DECODER_FSM_SPEC.md
```

---

## Quick Start

```bash
# 1. Generate LUT initialization files
cd phase4/tb
python gen_exp_lut.py     # → exp_lut.hex  (512 B)
python gen_silu_lut.py    # → silu_lut.hex (256 B)
python gen_rope_lut.py    # → rope_cos.hex + rope_sin.hex (16 KB)

# 2. Lint check
verilator --lint-only -sv -I phase2/sv \
  phase2/sv/pe.sv phase2/sv/systolic_array.sv \
  phase4/sv/tree_max.sv phase4/sv/tree_sum.sv \
  phase4/sv/exp_lut.sv  phase4/sv/recip_nr.sv  phase4/sv/softmax.sv \
  phase4/sv/silu_lut.sv phase4/sv/rmsnorm.sv   phase4/sv/qkv_proj.sv \
  phase4/sv/rope.sv     phase4/sv/dma_engine_v2.sv phase4/sv/kv_cache.sv \
  phase4/sv/mha.sv      phase4/sv/ffn.sv        phase4/sv/decoder_layer.sv

# 3. Yosys synthesis (update sky130 lib path in synth_decoder.ys first)
cd phase4/synth
yosys synth_decoder.ys
```

---

## Background

Six years at Samsung Electronics Foundry (Library FE DK & Verification):
SRAM compiler characterization, Liberty timing chain analysis, Fusion Compiler
RTL-to-netlist synthesis and STA, full DFT sign-off (JTAG/Logic BIST/Memory
BIST/ATPG cross-vendor), Palladium/Zebu emulation, and production RTL design
of the DNA BIST controller for eFlash and eMRAM.

This portfolio translates that physical design intuition into AI accelerator RTL.
Every number in the key metrics table has a derivation. Every design decision
has a quantified trade-off. The recip_nr pipeline and the x_delay SRAM
optimization path are the kind of detail that only comes from running the
actual synthesis and reading the timing report.
