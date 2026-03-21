"""
Generate RoPE sin/cos LUT hex files.
256 positions × 32 rotation pairs × INT8 Q7 = 8 KB each (16 KB total).
θ_k = 10000^(-2k/64),  k = 0..31
cos_lut[m][k] = round(cos(m * θ_k) * 127), clipped to INT8.
"""
import math, os
os.makedirs(".", exist_ok=True)

MAX_SEQ  = 256
HEAD_DIM = 64
HALF_D   = HEAD_DIM // 2
BASE     = 10000.0
Q7       = 127

thetas = [BASE ** (-2 * k / HEAD_DIM) for k in range(HALF_D)]

cos_lut, sin_lut = [], []
cos_errs, sin_errs = [], []

for m in range(MAX_SEQ):
    for k in range(HALF_D):
        angle  = m * thetas[k]
        cos_f  = math.cos(angle)
        sin_f  = math.sin(angle)
        cos_q7 = max(-128, min(127, round(cos_f * Q7)))
        sin_q7 = max(-128, min(127, round(sin_f * Q7)))
        cos_lut.append(cos_q7)
        sin_lut.append(sin_q7)
        cos_errs.append(abs(cos_q7 / Q7 - cos_f))
        sin_errs.append(abs(sin_q7 / Q7 - sin_f))

for fname, lut in [("rope_cos.hex", cos_lut), ("rope_sin.hex", sin_lut)]:
    with open(fname, "w") as f:
        for v in lut:
            f.write(f"{int(v) & 0xFF:02x}\n")

size_kb = MAX_SEQ * HALF_D * 2 / 1024
print(f"rope_cos.hex + rope_sin.hex: {size_kb:.0f} KB total")
print(f"  cos max error: {max(cos_errs):.4f} ({max(cos_errs)*100:.2f}%)")
print(f"  Q7 resolution: {1/Q7*100:.2f}% — same as INT8 weight accuracy")
