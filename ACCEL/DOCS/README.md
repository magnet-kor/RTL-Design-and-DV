# ACCEL — LLM Accelerator: 8×8 Systolic Array Reuse

**Target:** Qwen 2.5-0.5B Transformer Decoder Layer
**Platform:** SystemVerilog RTL + Yosys (sky130 PDK, 200 MHz)
**Author:** Jungho Lee — Samsung Electronics Foundry, Library FE DK Engineer, 6 years

> The 8×8 Output Stationary Systolic Array (Phase 2, CNN inference)
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

## Key Metrics

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
| Synthesis | **sky130, 200 MHz** | Yosys + ABC |

---

## Directory Structure

```
ACCEL/
├── RTL/                      SystemVerilog design files
│   ├── pe.sv                 Processing Element — Output Stationary MAC (Phase 2)
│   ├── systolic_array.sv     8×8 OS Array — reused ×9 in Phase 4 (Phase 2)
│   ├── decoder_layer.sv      Top — 13-state dual-mode FSM (Prefill/Decode)
│   ├── qkv_proj.sv           QKV projection (tiled systolic, 3 passes)
│   ├── mha.sv                GQA attention (QKᵀ + softmax + AV + OutProj)
│   ├── ffn.sv                SwiGLU FFN (FC1 + SiLU/gate + FC2 + FC3)
│   ├── kv_cache.sv           KV write-before-read FSM (DRAM)
│   ├── dma_engine_v2.sv      AXI4 bidirectional DMA
│   ├── rmsnorm.sv            RMS normalization (6-stage pipeline, 22 cycles)
│   ├── rope.sv               Rotary position embedding (LUT-based, 16 KB)
│   ├── softmax.sv            Safe softmax pipeline (18 cycles)
│   ├── tree_max.sv           Binary tree MAX reduction
│   ├── tree_sum.sv           Binary tree SUM reduction
│   ├── exp_lut.sv            EXP look-up table (512 B ROM, 1 cycle)
│   ├── recip_nr.sv           Newton-Raphson reciprocal (9 cycles, 2-stage)
│   └── silu_lut.sv           SiLU look-up table (256 B ROM, 1 cycle)
├── GOLDEN/                   Python bit-accurate reference models
│   ├── model_analysis.py     FLOP / arithmetic intensity analysis
│   ├── kv_cache_analysis.py  KV memory sizing and DMA overhead
│   ├── softmax_golden.py     Fixed-point softmax reference
│   └── rmsnorm_rope_golden.py  RMSNorm and RoPE reference
├── TB/                       Testbench — LUT initialization scripts
│   ├── gen_exp_lut.py        → exp_lut.hex  (512 B)
│   ├── gen_silu_lut.py       → silu_lut.hex (256 B)
│   └── gen_rope_lut.py       → rope_cos.hex + rope_sin.hex (16 KB)
├── SYNTH/                    Yosys synthesis scripts
│   ├── synth_decoder.ys      Synthesis script (read → synth → write)
│   └── synth_abc.sdc         Timing constraints (200 MHz, sky130)
└── DOCS/                     Documentation
    ├── README.md             This file
    ├── ARCH_SPEC.md          Architecture specification + performance budget
    ├── DECODER_FSM_SPEC.md   13-state FSM state transition specification
    └── npu_block_diagram.png Block diagram
```

---

## Module Hierarchy

```
decoder_layer.sv                   (Top — 13-state FSM)
├── rmsnorm.sv × 2                 (22 cycles each)
│   └── tree_sum.sv
├── qkv_proj.sv                    (129,045 cycles)
│   └── systolic_array.sv ←─────  Phase 2 reused, instance #1-3
│       └── pe.sv × 64
├── rope.sv                        (1,024 cycles, 16 KB LUT)
├── kv_cache.sv                    (DRAM R/W FSM)
│   └── dma_engine_v2.sv           (AXI4 bidirectional)
├── mha.sv                         (GQA, QKᵀ+softmax+AV+OutProj)
│   ├── systolic_array.sv ←─────  Phase 2 reused, instance #4-6
│   └── softmax.sv
│       ├── tree_max.sv
│       ├── exp_lut.sv             (512 B ROM)
│       ├── tree_sum.sv
│       └── recip_nr.sv            (9 cycles, 2-stage pipeline)
└── ffn.sv                         (SwiGLU, 8.2 ms)
    ├── systolic_array.sv ←─────  Phase 2 reused, instance #7-9
    └── silu_lut.sv                (256 B ROM, 1 cycle)
```

---

## Architecture Decision Log

| Decision | Alternative | Rationale |
|----------|-------------|-----------|
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

---

## Quick Start

```bash
# 1. Generate LUT initialization files
cd ACCEL/TB
python gen_exp_lut.py     # → exp_lut.hex  (512 B)
python gen_silu_lut.py    # → silu_lut.hex (256 B)
python gen_rope_lut.py    # → rope_cos.hex + rope_sin.hex (16 KB)

# 2. Lint check
verilator --lint-only -sv \
  -I ACCEL/RTL \
  ACCEL/RTL/pe.sv ACCEL/RTL/systolic_array.sv \
  ACCEL/RTL/tree_max.sv ACCEL/RTL/tree_sum.sv \
  ACCEL/RTL/exp_lut.sv  ACCEL/RTL/recip_nr.sv  ACCEL/RTL/softmax.sv \
  ACCEL/RTL/silu_lut.sv ACCEL/RTL/rmsnorm.sv   ACCEL/RTL/qkv_proj.sv \
  ACCEL/RTL/rope.sv     ACCEL/RTL/dma_engine_v2.sv ACCEL/RTL/kv_cache.sv \
  ACCEL/RTL/mha.sv      ACCEL/RTL/ffn.sv        ACCEL/RTL/decoder_layer.sv

# 3. Yosys synthesis (update sky130 lib path in synth_decoder.ys first)
cd ACCEL/SYNTH
yosys synth_decoder.ys

# 4. Run golden models
cd ACCEL/GOLDEN
python model_analysis.py
python softmax_golden.py
```
