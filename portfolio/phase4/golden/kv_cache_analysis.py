"""
KV Cache Memory Analysis — Prefill vs Decode Mode
Quantifies DRAM bandwidth requirements and KV cache sizing for
autoregressive transformer inference with Grouped Query Attention.
"""
import math

config = {
    "hidden_size"          : 896,
    "num_attention_heads"  : 14,
    "num_key_value_heads"  : 2,      # GQA: 2 KV heads shared by 7 Q heads each
    "head_dim"             : 64,
    "intermediate_size"    : 4864,
    "num_layers"           : 24,
}

hw = {
    "freq_mhz"      : 200,
    "array_size"    : 8,
    "axi_width_b"   : 8,       # 64-bit AXI4 bus = 8 bytes/beat
    "burst_len"     : 16,      # 16-beat burst = 128 bytes/burst
}


def weight_bytes_per_layer(cfg):
    H   = cfg["hidden_size"]
    Hkv = cfg["num_key_value_heads"] * cfg["head_dim"]
    F   = cfg["intermediate_size"]
    attn = H*H + H*Hkv + H*Hkv + H*H     # Wq Wk Wv Wo
    ffn  = H*F + H*F + F*H                 # FC1 FC2 FC3 (SwiGLU)
    return attn + ffn


def kv_cache_bytes_per_layer(cfg, seq_len):
    """KV cache for one layer: seq_len steps × (K + V) × KV_DIM bytes."""
    kv_dim = cfg["num_key_value_heads"] * cfg["head_dim"]
    return seq_len * kv_dim * 2   # INT8, K and V


def dma_cycles(byte_count, hw):
    """AXI4 burst DMA transfer time in clock cycles."""
    bytes_per_burst = hw["axi_width_b"] * hw["burst_len"]
    num_bursts = math.ceil(byte_count / bytes_per_burst)
    return num_bursts * hw["burst_len"]


def arithmetic_intensity(cfg):
    """MAC per DRAM byte — determines memory vs compute bound."""
    total_mac  = 14_908_336   # decode seq=1, from model_analysis.py
    w_bytes    = weight_bytes_per_layer(cfg) * cfg["num_layers"]
    return total_mac / w_bytes


def analyze(cfg, hw, seq_len=512):
    W_layer  = weight_bytes_per_layer(cfg)
    W_total  = W_layer * cfg["num_layers"]
    kv_layer = kv_cache_bytes_per_layer(cfg, seq_len)
    kv_total = kv_layer * cfg["num_layers"]
    ai       = arithmetic_intensity(cfg)
    knee     = hw["array_size"]**2 / hw["axi_width_b"]

    kv_write_cycles = dma_cycles(kv_layer, hw)          # new K,V per layer
    kv_read_cycles  = dma_cycles(kv_total, hw)           # full history

    print(f"\n{'='*60}")
    print(f"  KV Cache Memory Analysis  (seq_len={seq_len})")
    print(f"{'='*60}")
    print(f"\n  Weight Memory:")
    print(f"    Per layer       : {W_layer/1024:.1f} KB")
    print(f"    24 layers total : {W_total/1024/1024:.1f} MB  (DRAM-resident)")

    print(f"\n  Arithmetic Intensity:")
    print(f"    AI    = {ai:.2f} MAC/byte")
    print(f"    Knee  = {knee:.1f} MAC/byte  (roofline boundary)")
    print(f"    Bound = {'memory ⚠' if ai < knee else 'compute'}")
    print(f"    HW utilization = {ai/knee*100:.1f}%")

    print(f"\n  KV Cache (per layer, seq_len={seq_len}):")
    print(f"    Size     = {kv_layer/1024:.1f} KB")
    print(f"    24 total = {kv_total/1024:.1f} KB = {kv_total/1024/1024:.2f} MB")
    print(f"    on-chip 256KB limit exceeded by {kv_total/(256*1024):.1f}x → DRAM")

    print(f"\n  DMA overhead per decode step:")
    print(f"    KV write  : {kv_write_cycles} cycles  ({kv_layer} bytes)")
    print(f"    KV read   : {kv_read_cycles} cycles  ({kv_total} bytes)")
    total_dma = kv_write_cycles + kv_read_cycles
    print(f"    Total DMA : {total_dma} cycles = {total_dma/hw['freq_mhz']/1e3*1e6:.1f} μs")

    print(f"\n  KV cache saves (vs recompute at step {seq_len}):")
    kv_recompute_mac = seq_len * cfg["num_key_value_heads"] * cfg["head_dim"] \
                       * cfg["hidden_size"] * 2 * cfg["num_layers"]
    print(f"    Recompute cost : {kv_recompute_mac/1e6:.1f}M MAC")
    print(f"    With cache     : 0 MAC   (loaded from DRAM)")
    print(f"    Savings factor : {kv_recompute_mac/(kv_read_cycles*64):.1f}x")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    analyze(config, hw, seq_len=256)
