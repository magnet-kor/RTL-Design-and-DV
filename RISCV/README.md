# RISCV — 5-Stage Pipelined RISC-V CPU (RV32I)

완전한 RISC-V RV32I 5단계 파이프라인 CPU. 데이터 포워딩, 해저드 검출, 2비트 포화 카운터 분기 예측기 포함.

**Author:** Jungho Lee — Samsung Electronics Foundry, Library FE DK Engineer, 6 years

---

## Features

| Feature | Detail |
|---------|--------|
| ISA | RISC-V RV32I — all instruction types (R / I / S / B / U / J) |
| Pipeline | 5 stages: IF → ID → EX → MEM → WB |
| Forwarding | EX-EX and MEM-EX paths; write-first register file |
| Hazard | Load-use stall detection (1-cycle bubble insertion) |
| Branch | EX-stage resolution; 1-cycle flush penalty; 2-bit predictor |
| Jump | JAL and JALR unconditional jump support |
| Memory | LB / LH / LW / LBU / LHU / SB / SH / SW |

---

## Directory Structure

```
RISCV/
├── README.md
├── RTL/                      Design RTL (SystemVerilog)
│   ├── riscv_pipeline.sv     Top-level 5-stage pipeline integration
│   ├── alu.sv                32-bit ALU (ADD SUB AND OR XOR SLL SRL SRA SLT SLTU LUI)
│   ├── alu_ctrl.sv           ALU control: funct3/funct7 → 4-bit alu_op
│   ├── control.sv            Main control unit: opcode → all pipeline signals
│   ├── regfile.sv            32×32 register file with write-first forwarding
│   ├── imm_gen.sv            Immediate generator for all RV32I formats
│   ├── forwarding_unit.sv    EX-EX and MEM-EX forwarding logic
│   ├── hdu.sv                Hazard Detection Unit (load-use stall)
│   └── branch_predictor.sv   2-bit saturating counter predictor (64 entries)
├── TB/                       Testbench
│   └── riscv_pipeline_tb.sv  22-point testbench (7 test cases)
├── SIM/                      Simulation scripts
│   └── run.sh                Build and simulate (iverilog)
└── DOCS/                     Documentation
    ├── DESIGN_NOTES.md       Key design decisions with quantitative justification
    └── INTERVIEW_QA.md       Interview Q&A covering all design choices
```

---

## Build and Simulate

[Icarus Verilog](https://github.com/steveicarus/iverilog) (v10+) 필요.

```bash
bash SIM/run.sh
# Optional: bash SIM/run.sh wave   (opens GTKWave)
```

Expected output:
```
Results: 22 PASS  /  0 FAIL
ALL TESTS PASSED
```

---

## Key Design Decision: Branch Resolution at EX Stage

**MEM-stage 해결의 문제:**

`load` 직후 `branch`가 오는 경우, load-use 스톨(동기: HDU가 IF/ID를 1사이클 동결)과
branch 플러시(조합: ID/EX 클리어)가 동일 클록 엣지에서 충돌.
EX 스톨 신호가 IF/ID를 홀딩하는 동안 MEM-stage 플러시가 ID/EX를 동시에 덮어써서
파이프라인이 불일치 상태가 됨.

**해결: branch 해결을 EX stage로 이동.**

결과:
- 플러시와 스톨이 더 이상 충돌하지 않음 (파이프라인 스테이지로 분리)
- Branch miss penalty: 3 cycles → **1 cycle**
- 2-bit 예측기 연동이 깔끔해짐

---

## Performance (Yosys synthesis, sky130 target)

| Metric | Value |
|--------|-------|
| CPI (no predictor) | 1.71 |
| CPI (2-bit predictor, loop-heavy) | ~1.45 |
| Max clock | ~2.7 GHz (~370 ps critical path) |
| Gate count | ~3,500 gates (+73% vs single-cycle) |
| Throughput gain | **1.58× single-cycle baseline** |

클록 추정은 파운드리 라이브러리의 FA 체인 게이트 딜레이 기반 —
Liberty 특성화 업무에서 매일 사용하는 방법과 동일.

---

## Foundry Experience Connection

Samsung Foundry 6년 경험이 본 설계에 직접 연결된 세 가지:

1. **크리티컬 패스 직관**: FA 딜레이를 노드별로 알기 때문에 클록 추정이 이론이 아닌 수치로 나옴.

2. **DFT 인식**: 모든 파이프라인 레지스터가 스캔 호환 — 스캔 체인 삽입을 막는 피드백 루프 없음.

3. **공정-성능 관계**: sky130(오픈 PDK) + Yosys를 명시적으로 타깃으로 하여
   실제 파운드리 테이프아웃에서 사용하는 RTL → 합성 → 타이밍 클로저 플로우를 시연.
