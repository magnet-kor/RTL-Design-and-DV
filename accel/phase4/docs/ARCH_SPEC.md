# Decoder Layer Architecture Specification

**Target model:** Qwen 2.5-0.5B  
**Implementation:** Fixed-point INT8, SystemVerilog RTL  
**Clock:** 200 MHz (5 ns period)

---

## Model Configuration

| Parameter | Value | Notes |
|-----------|-------|-------|
| hidden_size | 896 | |
| num_attention_heads | 14 | Q heads |
| num_key_value_heads | 2 | GQA — 7 Q heads share 1 KV head |
| head_dim | 64 | = 896 / 14 |
| intermediate_size | 4864 | FFN width (SwiGLU) |
| num_layers | 24 | |
| max_seq_len | 256 | limited by on-chip RoPE LUT budget |

---

## Performance Budget (Decode, seq=1)

| Block | Cycles | Time | MAC share |
|-------|--------|------|-----------|
| RMSNorm ×2 | 44 | 0.22 μs | — |
| QKV Projection | 129,045 | 0.645 ms | 17.6% |
| RoPE | 1,024 | 5.1 μs | — |
| KV Write + Read | 32 + 32s | variable | — |
| MHA (QKᵀ + AV + OutProj) | ~200K | ~1.0 ms | 12.3% |
| FFN (FC1 + FC2 + FC3) | 1,639,189 | 8.2 ms | **87.7%** |
| **Total / layer** | **~3,490,000** | **17.5 ms** | |
| **24 layers / token** | | **420 ms** | **2.4 tok/s** |

Arithmetic intensity = 1.05 MAC/byte → **memory-bound** (roofline knee = 8.0).  
HW utilization = 1.05 / 8.0 = **13.1%**.

---

## Memory Architecture

| Buffer | Size | Location |
|--------|------|----------|
| Activation buffer A | 64 KB | On-chip SRAM |
| Activation buffer B | 64 KB | On-chip SRAM (double-buffer) |
| Weight buffer | 128 KB | On-chip SRAM |
| RoPE LUT (cos + sin) | 16 KB | On-chip SRAM |
| KV Cache | 3.15 MB | DRAM (exceeds 256 KB by 12×) |

KV Cache per layer = MAX_SEQ × KV_DIM × 2 = 256 × 128 × 2 = 64 KB.  
24 layers total = 1.5 MB (seq=256); 3.15 MB at seq=512.

---

## Module Hierarchy

```
decoder_layer.sv                   (Top — 13-state FSM)
├── rmsnorm.sv × 2                 (22 cycles each)
│   └── tree_sum.sv
├── qkv_proj.sv                    (129,045 cycles)
│   └── systolic_array.sv ← ───── Phase 2 reused, instance #1-3
│       └── pe.sv × 64
├── rope.sv                        (1,024 cycles, 16 KB LUT)
├── kv_cache.sv                    (DRAM R/W FSM)
│   └── dma_engine_v2.sv           (AXI4 bidirectional)
├── mha.sv                         (GQA, QKᵀ+softmax+AV+OutProj)
│   ├── systolic_array.sv ← ───── Phase 2 reused, instance #4-6
│   └── softmax.sv
│       ├── tree_max.sv
│       ├── exp_lut.sv             (512 B ROM)
│       ├── tree_sum.sv
│       └── recip_nr.sv            (9 cycles, 2-stage pipeline)
└── ffn.sv                         (SwiGLU, 8.2 ms)
    ├── systolic_array.sv ← ───── Phase 2 reused, instance #7-9
    └── silu_lut.sv                (256 B ROM, 1 cycle)
```

**systolic_array.sv is instantiated once and time-multiplexed 9×/layer.**  
Sequential execution is justified: decode batch=1, data dependencies prevent parallelism.

---

## Key Design Decisions

**Output Stationary dataflow:** batch=1 inference eliminates weight reuse benefit of Weight Stationary. OS accumulates partial sums in PE registers. Drain Latency = 2×(SIZE−1) = 14 cycles.

**Reciprocal LUT for ISQRT:** the `/` operator synthesizes as an iterative divider (8–10 cycles, timing failure). Replaced with 256-entry reciprocal LUT (512 B): 1/x for x in [1,255] precomputed as `round(65536/x)`.

**recip_nr 2-stage pipeline:** 64-bit multiply in Newton-Raphson exceeded 5 ns critical path. Split into Phase 0 (S×x, 64-bit) and Phase 1 (update, INT32). Adds 4 cycles to softmax (14→18), impacts total layer by 56/3,490,000 = 0.0016%.

**÷896 as ×73 >> 16:** `round(65536/896) = 73`. Error = 0.18% — within INT8 precision (0.4%).

**>>3 for ÷√64:** head_dim=64, √64=8=2³. Zero-latency arithmetic right shift.

**GQA kv_head = q_head / 7:** KV Cache 7× smaller than full MHA (128 vs 896 B/step/layer).
