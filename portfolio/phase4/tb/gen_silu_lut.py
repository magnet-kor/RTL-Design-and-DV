"""
Generate SiLU LUT hex file for FFN gate activation.
256 entries × 1 byte = 256 bytes.
lut[i] = round(SiLU(i - 128)), clipped to INT8.
SiLU(x) = x / (1 + exp(-x)).
"""
import math, os
os.makedirs(".", exist_ok=True)

lut, errors = [], []
for i in range(256):
    x = i - 128
    silu = x / (1.0 + math.exp(-x)) if x > -30 else 0.0
    q = max(-128, min(127, round(silu)))
    lut.append(q)
    errors.append(abs(q - silu))

with open("silu_lut.hex", "w") as f:
    for v in lut:
        f.write(f"{int(v) & 0xFF:02x}\n")

print(f"silu_lut.hex: {len(lut)} entries")
print(f"  max quantization error: {max(errors):.4f} ({max(errors)/128*100:.3f}%)")
print(f"  INT8 precision limit:   {0.5/128*100:.3f}%")
