"""
Generate EXP LUT hex file for softmax.
256 entries × 2 bytes = 512 bytes.
lut[i] = round(exp(i - 255) * 256), clamped to [0, 65535].
"""
import math, os
os.makedirs(".", exist_ok=True)

lut = []
for i in range(256):
    val = min(round(math.exp(i - 255) * 256), 65535)
    lut.append(val)

with open("exp_lut.hex", "w") as f:
    for v in lut:
        f.write(f"{v:04x}\n")

print(f"exp_lut.hex: {len(lut)} entries")
print(f"  lut[255] = {lut[255]}  (exp(0)*256 = 256)")
print(f"  lut[254] = {lut[254]}  (exp(-1)*256 ≈ 94)")
print(f"  lut[0]   = {lut[0]}    (exp(-255)*256 ≈ 0)")
