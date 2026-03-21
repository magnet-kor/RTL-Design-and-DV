# Interview Q&A — RISC-V Pipeline CPU

---

## Pipeline Hazards

**Q: Why did you move branch resolution from MEM to EX?**

When a `load` was immediately followed by a `branch`, two control signals
fired in the same clock cycle:
the load-use stall (synchronous — HDU holds IF/ID for 1 cycle by gating `pc_write`)
and the branch flush (combinatorial — `always_comb` clears ID/EX immediately).

The EX stall was freezing IF/ID while the MEM flush was simultaneously overwriting
ID/EX in the same clock edge. The update order was non-deterministic, and the wrong
instruction occasionally proceeded past ID into EX.

Moving branch resolution to EX separates the two events by one pipeline stage:
the stall completes in one cycle, the flush fires in the next — no conflict.
Side benefit: miss penalty drops from 3 cycles to 1 cycle.

---

**Q: What hazard can forwarding not resolve?**

The load-use hazard. When `lw x1, 0(x2)` is immediately followed by
`add x3, x1, x4`, the loaded value does not exist until after the MEM stage
of the `lw`, which is one cycle after the `add` needs it in EX.

Forwarding moves an existing value earlier in the pipeline — it cannot produce
a value that has not been computed yet. The HDU inserts a 1-cycle bubble.
The compiler can eliminate this stall by scheduling an independent instruction
into the load-delay slot.

---

**Q: Walk through your CPI derivation.**

```
Base CPI:         1.00
Load-use stalls:  ~8% of instructions are load-then-use → 0.08 × 1 = 0.08
Branch penalty:   ~20% are branches, 100% miss (no predictor) → 0.20 × 1 = 0.20
Other:            ~0.43 (structural stalls, WB conflicts)
Total:            ~1.71
```

Multiplied by the 2.7× clock improvement from pipelining:
effective throughput = (1/1.71) × 2.7 = **1.58× single-cycle baseline**.

With the 2-bit predictor on loop-heavy code, CPI drops to ~1.45 because
inner-loop branches stay in the Strongly Taken state and only mispredict once
per loop invocation (on exit).

---

**Q: How does your forwarding unit handle the priority between EX-MEM and MEM-WB?**

EX-MEM always takes priority over MEM-WB when both match.

If instruction N writes x1, and instruction N+1 and N+2 both read x1,
then when N+2 is in EX:
- EX-MEM path carries N+1's result (one instruction back — newer)
- MEM-WB path carries N's result   (two instructions back — older)

The correct value for N+2 is N+1's result, so EX-MEM wins.
The `!= 5'b0` guard on both paths prevents false matches against x0
(hardwired zero in RV32I — writes to x0 are legal but have no architectural effect).

---

**Q: Explain the 2-bit branch predictor design and why 2-bit outperforms 1-bit.**

The predictor is a 64-entry direct-mapped table. Each entry holds a 2-bit
saturating counter; the MSB determines the prediction (1=taken, 0=not-taken).

A 1-bit predictor flips its state on every misprediction, so for a loop it
misses on exit *and* on the first entry of the next loop invocation — two misses
per loop execution. A 2-bit counter absorbs a single misprediction without
changing the predicted outcome. A loop therefore misses only once per invocation
(on exit, when the counter moves from Strongly Taken to Weakly Taken), and
the prediction is immediately restored on re-entry.

For the sum-1-to-10 loop in the test suite this means 1 miss out of 10 iterations:
~90% accuracy vs ~82% for a 1-bit predictor.

---

## Micro-architecture

**Q: Why is write-first forwarding in the register file necessary?**

In the 5-stage pipeline, WB writes and ID reads happen in the same clock cycle.
Without the bypass, the instruction entering ID would see the stale pre-WB value
even though the forwarding unit expects the register file to be up-to-date.

The fix is a combinatorial bypass in the read logic:
```
rd1 = (we && wa == ra1) ? wd : regs[ra1];
```
This is equivalent to a MEM-WB → ID forwarding path, but it is more cleanly
expressed at the register file boundary.

---

**Q: How does the LUI instruction flow through your pipeline?**

LUI writes `{imm20, 12'b0}` to a register. In the pipeline:

1. **ID**: control unit sets `lui=1`, `reg_write=1`, `alu_src=1`
2. **EX**: ALU control selects `alu_op=1010` (pass-through), ALU output = immediate
3. **MEM**: no memory access, result passes through
4. **WB**: `mem_to_reg=0` so ALU result is written to `rd`

No special hardware — LUI reuses the immediate-passthrough ALU operation.
AUIPC adds PC to the immediate; same path with the adder output instead.

---

## Foundry Experience Connection

**Q: How does your foundry background change how you approach RTL design?**

Three concrete ways:

**Critical path awareness before synthesis.**
Knowing FA-chain delay per technology node makes clock estimates first-principles
rather than guesswork. The 370 ps critical path estimate for the ALU→branch-condition
path was derived from Liberty timing arcs — the same data format I characterise
and maintain daily. Yosys confirmed the estimate within 15%.

**DFT compatibility from the first commit.**
Every pipeline register in this design uses a standard `always_ff` with
synchronous or asynchronous reset — no feedback loops, no latches, no
uncontrolled reset fanout. These are the exact patterns that cause scan
chain insertion failures in Fusion Compiler. I write RTL with DFT constraints
as a first-class input, not as a back-end review step.

**Process–performance intuition.**
Understanding how the same RTL scales from 28 nm to 5 nm (clock ×3–4,
power ÷10, area ÷10) means I can reason about architectural trade-offs —
why an 8×8 systolic array at 5 nm changes the energy equation compared to
the same array at 28 nm — without needing back-end results first.
