# NPU — Weight Stationary Systolic Array NPU

8×8 Weight Stationary Systolic Array NPU with APB/AXI4 interfaces and full UVM verification.

---

## Architecture Overview

```
CPU ──APB──► host_interface ──► control_unit ──► systolic_array_ws (8×8 WS)
                                     │                    │
                              sram_sp (256 KB)       accumulator
                                     │                    │
              DRAM ◄──AXI4──► dma_engine          post_proc (ReLU + INT8)
                                                          │
                                                    DRAM (output write)
```

**Data Flow:**
1. CPU writes config via APB (weight/activation/output addresses, scale factor)
2. DMA reads weights from DRAM → on-chip SRAM
3. SRAM → `wt_col` → Systolic Array (weight load, 8 cycles)
4. DMA reads activations from DRAM → `act_buf`
5. `act_buf` → Systolic Array (compute, 1 cycle/column)
6. Partial sums → Accumulator (multi-tile support)
7. Accumulator → Post-processor (ReLU + scale >> + INT8 clamp)
8. DMA writes output to DRAM

---

## Key Parameters

| Parameter | Value |
|-----------|-------|
| Array size | 8×8 (64 PE) |
| Data width | INT8 |
| Accumulator | INT32 |
| SRAM | 256 KB single-port |
| AXI4 data bus | 64-bit |
| APB registers | 6 (wgt_addr, act_addr, out_addr, scale, start, status) |

---

## Directory Structure

```
NPU/
├── RTL/                  RTL design files
│   ├── npu_top_ws.sv     Top-level (module hierarchy + port connections)
│   ├── control_unit.sv   Main FSM + SRAM weight buffer
│   ├── systolic_array_ws.sv  8×8 WS systolic array
│   ├── pe_ws.sv          Weight Stationary Processing Element (MAC)
│   ├── accumulator.sv    Partial-sum accumulation (multi-tile)
│   ├── post_proc.sv      INT32→INT8: ReLU + scale + clamp
│   ├── dma_engine.sv     AXI4 master (DRAM read/write)
│   ├── host_interface.sv APB slave — CPU configuration registers
│   ├── sram_sp.sv        Single-port SRAM model
│   ├── dram_model.sv     DRAM behavioral model (simulation)
│   ├── dram_backdoor_if.sv  Backdoor interface for testbench
│   └── npu_if.sv         SystemVerilog interface (DUT signals)
├── UVM/                  UVM verification environment
│   ├── tb_npu_uvm.sv     Top-level testbench + clock/reset
│   ├── npu_test.sv       Test class (scenario orchestration)
│   ├── npu_agent_env.sv  UVM env — agent + scoreboard + coverage
│   ├── npu_driver.sv     Stimulus driver (APB transactions)
│   ├── npu_monitor.sv    Bus monitor (APB + AXI4 observe)
│   ├── npu_scoreboard.sv Reference model + result check
│   ├── npu_coverage.sv   Functional coverage groups
│   ├── npu_sequences.sv  Sequence library (basic, stress, corner)
│   └── npu_seq_item.sv   Transaction item definition
├── TB/                   Standalone testbench
│   └── tb_sram_sim.sv    SRAM standalone simulation
└── SIM/                  Simulation outputs
    ├── sim_sram          Compiled simulation binary
    └── tb_sram.vcd       VCD waveform dump
```

---

## Module Details

### `control_unit.sv` — Main FSM
Manages the full inference pipeline: DMA weight load → SRAM store → weight feed to SA → DMA activation load → compute → accumulate → post-process → DMA output write. Contains `sram_sp` instance for weight buffering.

### `systolic_array_ws.sv` — 8×8 WS Array
Weight Stationary dataflow: weights preloaded into PE registers, activations propagate left-to-right. 64 PEs compute INT8 MAC in parallel. Drain latency = 2×(8−1) = 14 cycles.

### `accumulator.sv` — Multi-tile Accumulator
Accumulates partial sums across multiple AXI4 tiles. `acc_clr` resets between independent output rows; `acc_en` gates accumulation.

### `post_proc.sv` — Post-Processor
INT32 → INT8 pipeline: ReLU (zero negative values) → arithmetic right-shift by `scale[4:0]` → clamp to [−128, 127].

### `dma_engine.sv` — AXI4 Master
Supports both read (DRAM → internal) and write (internal → DRAM) bursts. `dma_wr` selects direction. Burst length configurable via `dma_beats`.

---

## Simulation

```bash
# SRAM standalone test
cd NPU/SIM
./sim_sram
# or view waveform
gtkwave tb_sram.vcd

# UVM testbench (requires VCS or Questa)
vcs -sverilog -ntb_opts uvm \
    NPU/RTL/*.sv NPU/UVM/*.sv \
    -top tb_npu_uvm
./simv
```
