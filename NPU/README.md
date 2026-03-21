# NPU — Weight Stationary Systolic Array NPU

8×8 Weight Stationary Systolic Array NPU. APB/AXI4 인터페이스 + 완전한 UVM 검증 환경.

**Author:** Jungho Lee — Samsung Electronics Foundry, Library FE DK Engineer, 6 years

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
1. CPU → APB로 설정 (weight/activation/output 주소, scale factor)
2. DMA: DRAM → on-chip SRAM (weight load)
3. SRAM `wt_col` → Systolic Array (weight preload, 8 cycles)
4. DMA: DRAM → `act_buf` (activation load)
5. `act_buf` → Systolic Array (compute, 1 cycle/column)
6. 부분합 → Accumulator (multi-tile 지원)
7. Accumulator → Post-processor (ReLU + scale >> + INT8 clamp)
8. DMA: 결과 → DRAM (output write)

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
├── README.md
├── RTL/                      Design RTL (synthesizable)
│   ├── npu_top_ws.sv         Top-level (module hierarchy + port connections)
│   ├── control_unit.sv       Main FSM + SRAM weight buffer
│   ├── systolic_array_ws.sv  8×8 WS systolic array
│   ├── pe_ws.sv              Weight Stationary Processing Element (MAC)
│   ├── accumulator.sv        Partial-sum accumulation (multi-tile)
│   ├── post_proc.sv          INT32→INT8: ReLU + scale + clamp
│   ├── dma_engine.sv         AXI4 master (DRAM read/write)
│   ├── host_interface.sv     APB slave — CPU configuration registers
│   └── sram_sp.sv            Single-port SRAM model
├── UVM/                      UVM verification environment
│   ├── tb_npu_uvm.sv         Top-level testbench + clock/reset
│   ├── npu_test.sv           Test class (scenario orchestration)
│   ├── npu_agent_env.sv      UVM env — agent + scoreboard + coverage
│   ├── npu_driver.sv         Stimulus driver (APB transactions)
│   ├── npu_monitor.sv        Bus monitor (APB + AXI4 observe)
│   ├── npu_scoreboard.sv     Reference model + result check
│   ├── npu_coverage.sv       Functional coverage groups
│   ├── npu_sequences.sv      Sequence library (basic, stress, corner)
│   ├── npu_seq_item.sv       Transaction item definition
│   ├── npu_if.sv             SystemVerilog interface (DUT signals)
│   ├── dram_model.sv         DRAM behavioral model (simulation only)
│   └── dram_backdoor_if.sv   Backdoor interface for scoreboard access
├── TB/                       Standalone testbench
│   └── tb_sram_sim.sv        SRAM standalone simulation
└── SIM/                      Simulation outputs
    ├── sim_sram              Compiled simulation binary
    └── tb_sram.vcd           VCD waveform dump
```

---

## Module Details

### `control_unit.sv` — Main FSM
DMA weight load → SRAM store → weight feed to SA → DMA activation load → compute → accumulate → post-process → DMA output write 전체 파이프라인 관리. `sram_sp` 인스턴스를 내부적으로 포함.

### `systolic_array_ws.sv` — 8×8 WS Array
Weight Stationary 데이터플로우: 가중치를 PE 레지스터에 프리로드 후 고정, activation이 좌→우로 전파. 64개 PE가 INT8 MAC 병렬 연산. 드레인 레이턴시 = 2×(8−1) = 14 사이클.

### `accumulator.sv` — Multi-tile Accumulator
여러 AXI4 타일에 걸친 부분합 누적. `acc_clr`로 독립 출력 행 간 리셋, `acc_en`으로 누적 게이팅.

### `post_proc.sv` — Post-Processor
INT32 → INT8 파이프라인: ReLU (음수 → 0) → 산술 우시프트 `scale[4:0]` → [-128, 127] 클램프.

### `dma_engine.sv` — AXI4 Master
읽기(DRAM → 내부)와 쓰기(내부 → DRAM) 버스트 모두 지원. `dma_wr`로 방향 선택. `dma_beats`로 버스트 길이 설정.

---

## UVM Verification

| 컴포넌트 | 역할 |
|----------|------|
| `npu_driver.sv` | APB 트랜잭션 구동 |
| `npu_monitor.sv` | APB + AXI4 버스 관찰 |
| `npu_scoreboard.sv` | 레퍼런스 모델 계산 + 결과 비교 |
| `npu_coverage.sv` | 기능 커버리지 수집 |
| `npu_sequences.sv` | Basic / Stress / Corner 시퀀스 라이브러리 |
| `dram_model.sv` | DRAM 행동 모델 (시뮬레이션 전용) |
| `dram_backdoor_if.sv` | 스코어보드용 백도어 인터페이스 |

---

## Simulation

```bash
# SRAM 단독 테스트
cd NPU/SIM
./sim_sram
# 파형 확인
gtkwave tb_sram.vcd

# UVM 테스트벤치 (VCS or Questa)
vcs -sverilog -ntb_opts uvm-1.2 \
    NPU/RTL/*.sv NPU/UVM/*.sv \
    -top tb_npu_uvm
./simv
```
