"""
Qwen 2.5-0.5B Decoder Layer — FLOP and Latency Analysis
Arithmetic intensity analysis for hardware accelerator sizing.
"""

config = {
    "hidden_size"          : 896,
    "num_attention_heads"  : 14,
    "num_key_value_heads"  : 2,       # GQA
    "head_dim"             : 64,      # = 896 / 14
    "intermediate_size"    : 4864,
    "num_layers"           : 24,
}

HW = {
    "array_size" : 8,           # 8x8 systolic array -> 64 MAC/cycle
    "freq_mhz"   : 200,
    "axi_width_b": 8,           # 64-bit AXI4
}


def compute_mac_per_layer(cfg, seq_len=1):
    H    = cfg["hidden_size"]
    Hkv  = cfg["num_key_value_heads"] * cfg["head_dim"]  # GQA KV dim
    F    = cfg["intermediate_size"]
    S    = seq_len

    return {
        "Q Proj"     : H * H,
        "K Proj"     : H * Hkv,
        "V Proj"     : H * Hkv,
        "QKt (attn)" : S * cfg["head_dim"] * cfg["num_attention_heads"],
        "AV (attn)"  : S * cfg["head_dim"] * cfg["num_attention_heads"],
        "Out Proj"   : H * H,
        "FFN FC1"    : H * F,
        "FFN FC2"    : H * F,
        "FFN FC3"    : F * H,
    }


def compute_cycles(mac, hw):
    mac_per_cycle = hw["array_size"] ** 2
    mac_per_tile  = mac_per_cycle * hw["array_size"]
    num_tiles     = max(1, mac // mac_per_tile)
    return (mac // mac_per_cycle) + num_tiles * (hw["array_size"] - 1)


def analyze(cfg, hw, seq_len=1):
    blocks = compute_mac_per_layer(cfg, seq_len)
    total_mac    = sum(blocks.values())
    total_cycles = sum(compute_cycles(v, hw) for v in blocks.values())
    time_ms      = total_cycles / (hw["freq_mhz"] * 1e6) * 1e3

    # Arithmetic intensity: MAC / DRAM bytes
    weight_bytes = (cfg["hidden_size"] ** 2                          # Wq
                  + cfg["hidden_size"] * cfg["num_key_value_heads"] * cfg["head_dim"] * 2  # Wk, Wv
                  + cfg["hidden_size"] ** 2                          # Wo
                  + cfg["hidden_size"] * cfg["intermediate_size"] * 3) # FFN

    ai = total_mac / weight_bytes

    print(f"\n{'='*60}")
    print(f"  Decoder Layer Analysis  (seq_len={seq_len})")
    print(f"{'='*60}")
    print(f"  {'Block':<14} {'MAC':>12}  {'Share':>6}")
    print(f"  {'-'*38}")
    for name, mac in blocks.items():
        share = mac / total_mac * 100
        print(f"  {name:<14} {mac:>12,}  {share:>5.1f}%")
    print(f"  {'-'*38}")
    print(f"  {'Total':<14} {total_mac:>12,}  100.0%")
    print(f"\n  Latency       : {time_ms:.2f} ms / layer")
    print(f"  24 layers     : {time_ms * 24:.1f} ms / token")
    print(f"  Throughput    : {1000 / (time_ms * 24):.1f} tokens/s")
    print(f"\n  Arithmetic Intensity : {ai:.2f} MAC/byte")
    roofline_knee = hw["array_size"]**2 / hw["axi_width_b"]
    print(f"  Roofline knee        : {roofline_knee:.1f} MAC/byte")
    print(f"  Bound                : {'memory' if ai < roofline_knee else 'compute'}")
    utilization = ai / roofline_knee * 100
    print(f"  HW utilization       : {utilization:.1f}%")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    print("[Decode mode — seq_len = 1]")
    analyze(config, HW, seq_len=1)
    print("[Prefill mode — seq_len = 128]")
    analyze(config, HW, seq_len=128)
