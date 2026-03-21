"""
Hardware-Accurate Golden Models: RMSNorm and RoPE
Both models implement integer arithmetic matching the RTL exactly.
"""
import math
import numpy as np

# ── RMSNorm ──────────────────────────────────────────────────────────────────

def isqrt_newton(n, iters=4):
    """Integer square root via Newton-Raphson: x_{n+1} = (x_n + n/x_n) / 2."""
    if n == 0:
        return 0
    x = 1 << ((n.bit_length() + 1) // 2)
    for _ in range(iters):
        x = (x + n // x) // 2
    return x


def rmsnorm_hw(x, gamma, N=None):
    """
    Hardware-accurate RMSNorm.
    x, gamma: INT8 arrays of length N
    Returns: INT8 normalized output

    Pipeline:
      Stage 1: x^2 (element-wise, 1 cycle)
      Stage 2: sum(x^2) tree reduction (log2(N) cycles)
      Stage 3: / N via Q16 multiply (1 cycle)
      Stage 4: sqrt via Newton-Raphson (8 cycles, 4 iters)
      Stage 5: reciprocal (1 cycle)
      Stage 6: scale by gamma (1 cycle)
    """
    x     = [int(v) for v in x]
    g     = [int(v) for v in gamma]
    n     = len(x) if N is None else N

    # Stage 1-2: sum of squares
    sq_sum = sum(xi * xi for xi in x)

    # Stage 3: / N using Q16 constant  (1/N * 2^16, rounded)
    recip_n_q16 = round(65536 / n)
    mean_sq     = (sq_sum * recip_n_q16) >> 16

    # Stage 4: integer sqrt
    rms = isqrt_newton(mean_sq, iters=4)
    if rms == 0:
        rms = 1

    # Stage 5: reciprocal in Q7 (128/rms * 128 = 16384/rms)
    recip_rms = (128 * 128) // rms

    # Stage 6: normalize and scale
    out = []
    for xi, gi in zip(x, g):
        xr     = (xi * recip_rms) >> 7       # x / rms, Q7
        scaled = (xr * gi) >> 7               # * gamma (Q7)
        out.append(max(-128, min(127, scaled)))
    return out


# ── RoPE LUT ─────────────────────────────────────────────────────────────────

def build_rope_lut(seq_len=256, head_dim=64, base=10000):
    """
    Precompute RoPE sin/cos tables.
    INT8 Q7 format: 1.0 maps to 127.
    LUT size: seq_len * head_dim/2 * 2 (cos+sin) * 1 byte = 16KB for seq=256.
    """
    half_d  = head_dim // 2
    cos_lut = np.zeros((seq_len, half_d), dtype=np.int8)
    sin_lut = np.zeros((seq_len, half_d), dtype=np.int8)

    for m in range(seq_len):
        for k in range(half_d):
            theta     = m * (base ** (-2 * k / head_dim))
            cos_lut[m][k] = max(-128, min(127, round(math.cos(theta) * 127)))
            sin_lut[m][k] = max(-128, min(127, round(math.sin(theta) * 127)))

    lut_kb = seq_len * half_d * 2 / 1024
    print(f"  RoPE LUT: {seq_len}*{half_d}*2 = {lut_kb:.0f} KB")
    return cos_lut, sin_lut


def rope_hw(q, pos_m, cos_lut, sin_lut):
    """
    Apply RoPE rotation to query vector q at position pos_m.
    Rotation pairs: head_dim/2 pairs of (q[2k], q[2k+1]).
    Scaling: >>7 to remove Q7 factor after INT8*INT8 multiply.
    """
    head_dim = len(q)
    half_d   = head_dim // 2
    q_out    = [0] * head_dim

    for k in range(half_d):
        q0 = int(q[2*k])
        q1 = int(q[2*k+1])
        c  = int(cos_lut[pos_m][k])
        s  = int(sin_lut[pos_m][k])
        q_out[2*k]   = max(-128, min(127, (q0 * c - q1 * s) >> 7))
        q_out[2*k+1] = max(-128, min(127, (q0 * s + q1 * c) >> 7))

    return q_out


if __name__ == "__main__":
    import numpy as np
    np.random.seed(42)

    # --- RMSNorm verification ---
    N  = 8
    x  = list(np.random.randint(-64, 64, N))
    g  = [64] * N   # gamma = 0.5 in Q7
    out = rmsnorm_hw(x, g, N)
    print(f"RMSNorm  x={x}")
    print(f"         out={out}")

    # Float reference
    xf  = np.array(x, dtype=float)
    rms = math.sqrt(sum(xi**2 for xi in x) / N)
    ref = [max(-128, min(127, round(xi / rms * 64 / 128))) for xi in x]
    print(f"         ref={ref}")

    # --- RoPE verification ---
    cos_lut, sin_lut = build_rope_lut(seq_len=8, head_dim=16)
    q  = list(range(-8, 8))
    qr = rope_hw(q, pos_m=2, cos_lut=cos_lut, sin_lut=sin_lut)
    print(f"\nRoPE  q[0:4]  = {q[:4]}")
    print(f"      qr[0:4] = {qr[:4]}  (pos=2)")
