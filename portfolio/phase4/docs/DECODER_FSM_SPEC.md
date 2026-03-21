# Decoder Layer Dual-Mode FSM Specification

## Overview

The decoder_layer FSM controls one complete layer execution for both Prefill
(step_id=0) and Decode (step_id>0) modes. The FSM is identical for both modes
because KV write→read is required in both: Prefill must store the first K/V
pair to DRAM so that subsequent decode steps can load it as history.

The only difference between modes is `hist_len` (passed to MHA):
- Prefill: hist_len = 1
- Decode:  hist_len = step_id + 1

## States (13 total)

| State | Function | Duration | Transition condition |
|-------|----------|----------|---------------------|
| DL_IDLE | Wait for start | — | start == 1 |
| DL_RMSNORM1 | RMSNorm(x_in) → x_norm1 | 22 cycles | rn1_vout |
| DL_QKV | QKV projection → Q, K, V | 129,045 cycles | qkv_done |
| DL_ROPE | RoPE rotation → Q_rot, K_rot | 1,024 cycles | rope_done |
| DL_KV_WRITE | (kv_cache FSM handles internally) | 32 cycles | automatic |
| DL_KV_READ | KV history → on-chip | 32×(s+1) cycles | kvc_done |
| DL_MHA | QKᵀ + softmax + AV + OutProj | ~200K cycles | mha_done |
| DL_RESID1 | x2 = x_in_buf + attn_out | 1 cycle | automatic |
| DL_RMSNORM2 | RMSNorm(x2) → x_norm2 | 22 cycles | rn2_vout |
| DL_FFN | SwiGLU FFN → ffn_out | 1,639,189 cycles | ffn_done |
| DL_RESID2 | x_out = x2 + ffn_out | 1 cycle | automatic |
| DL_OUTPUT | Output registration | 1 cycle | automatic |
| DL_DONE | Assert done pulse | 1 cycle | automatic |

## x_in Latching

`x_in_buf` is loaded from port `x_in` at the DL_IDLE→DL_RMSNORM1 transition.
This preserves the original input value for Residual Add at DL_RESID1,
which occurs ~3.49M cycles after start — well beyond any guarantee of
external port stability.

## KV DRAM Address Layout

```
KV_BASE = 0x8000_0000 (configured by host)
K_addr(layer l, step s) = KV_BASE + l * 65536 + s * 256
V_addr(layer l, step s) = K_addr(l, s) + 128

Layer stride = MAX_SEQ * KV_DIM * 2 = 256 * 128 * 2 = 65536 B = 64 KB
Step stride  = KV_DIM * 2            = 128 * 2       = 256 B
```

## Signal Timing

All submodule `start` signals are pulsed for exactly 1 cycle at state
entry using registered control signals (default=0 in always_ff).
Combinational `start = (state == TARGET)` is avoided to prevent
multi-cycle re-triggering during long-running states.

## Total Latency

Layer latency ≈ 3,490,000 cycles = 17.5 ms @ 200 MHz.
24 layers = 420 ms/token = 2.4 tokens/second.
KV DMA overhead at step 255: 8,224 cycles = 0.24% of layer total.
