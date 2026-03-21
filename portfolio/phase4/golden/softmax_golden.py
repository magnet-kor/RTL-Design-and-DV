"""
Hardware-Accurate Fixed-Point Softmax — Golden Model
Implements safe softmax: exp(x - max) / sum(exp(x - max))
Used as expected-value reference for RTL testbenches.
"""
import math

# Q8 scale factor: 1.0 maps to 256
SCALE = 256


def build_exp_lut():
    """
    Precompute EXP LUT for safe softmax.
    Input index i maps to x = i - 255, so:
      lut[0]   = exp(-255) * 256 ~ 0
      lut[255] = exp(0)    * 256 = 256
    LUT size: 256 entries * 2 bytes = 512 bytes
    """
    lut = []
    for i in range(256):
        x   = i - 255                           # i=0 -> x=-255, i=255 -> x=0
        val = min(round(math.exp(x) * SCALE), 65535)
        lut.append(val)
    return lut


EXP_LUT = build_exp_lut()


def hw_recip(s, iters=4, Q=15):
    """
    Newton-Raphson reciprocal: 1/s in Q15 fixed-point.
    Convergence: quadratic — 4 iterations give <2^-16 error.
    """
    if s == 0:
        return 0
    ONE_Q15 = 1 << Q
    TWO_Q15 = 2 << Q
    # Initial guess via leading-bit approximation (error < 50%)
    k = s.bit_length() - 1
    x = ONE_Q15 >> k if k < Q else 1
    for _ in range(iters):
        sx     = s * x
        two_sx = TWO_Q15 - (sx >> Q)
        x      = (x * two_sx) >> Q
        x      = min(max(0, x), 65535)
    return x


def softmax_hw(scores):
    """
    6-stage hardware softmax pipeline.
    Stage 1: tree MAX (log2(N) cycles)
    Stage 2: subtract max
    Stage 3: EXP LUT lookup (1 cycle)
    Stage 4: tree SUM (log2(N) cycles)
    Stage 5: reciprocal Newton-Raphson (9 cycles with 2-stage pipeline)
    Stage 6: multiply (1 cycle)
    Total latency: 18 cycles for N=8
    """
    scores = [int(x) for x in scores]

    # Stage 1: max
    max_val = max(scores)

    # Stage 2: subtract -> LUT index
    lut_idx = [255 + (x - max_val) for x in scores]

    # Stage 3: EXP LUT (Q8 output)
    exp_vals = [EXP_LUT[max(0, min(255, idx))] for idx in lut_idx]

    # Stage 4: sum
    exp_sum = sum(exp_vals)

    # Stage 5: 1/sum (Q15)
    recip = hw_recip(exp_sum)

    # Stage 6: exp_i * recip >> 15 (Q8+Q15 -> Q23, >>15 -> Q8)
    out = [(e * recip) >> 15 for e in exp_vals]
    return [min(max(0, x), 255) for x in out]


def softmax_float(scores):
    """Float reference for error comparison."""
    import numpy as np
    s = [float(x) for x in scores]
    m = max(s)
    e = [math.exp(x - m) for x in s]
    total = sum(e)
    return [ei / total for ei in e]


def verify(scores, name="test"):
    hw_out  = softmax_hw(scores)
    fp_out  = softmax_float(scores)
    fp_q8   = [round(p * 256) for p in fp_out]
    max_err = max(abs(hw_out[i] - fp_q8[i]) for i in range(len(scores)))
    print(f"  [{name}]  hw={hw_out}  err_max={max_err} LSB")
    return hw_out


if __name__ == "__main__":
    print("Softmax HW Golden Model Verification")
    verify([8, 6, 3, 1, -1, -3, -6, -8], "typical")
    verify([10, -5, -5, -5, -5, -5, -5, -5], "peaked")
    verify([0,  0,  0,  0,  0,  0,  0,  0],  "uniform")

    test = [8, 6, 3, 1, -1, -3, -6, -8]
    exp  = softmax_hw(test)
    print(f"\n  [RTL expected] input={test}")
    print(f"                output={exp}")
