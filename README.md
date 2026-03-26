# RTL Design & Verification

**Author:** Jungho Lee — Samsung Electronics Foundry, Library FE DK Engineer, 6 years
**Stack:** SystemVerilog RTL · UVM · Yosys (sky130) · Verilator · Python

---

## Repository Structure

```
RTL-Design-and-DV/
├── NPU/      Weight Stationary NPU — 8×8 WS Systolic Array + UVM
├── ACCEL/    LLM Accelerator — Transformer Decoder Layer + UVM
└── RISCV/    RISC-V RV32I 5-Stage Pipelined CPU
```

모든 프로젝트는 동일한 서브 디렉터리 규칙을 따릅니다:

| 디렉터리  | 내용                              |
|-----------|-----------------------------------|
| `RTL/`    | 합성 가능한 설계 RTL (SystemVerilog) |
| `UVM/`    | UVM 검증 환경                     |
| `TB/`     | 단독 테스트벤치 / LUT 초기화 스크립트 |
| `SIM/`    | 시뮬레이션 스크립트 / 출력 파일     |
| `SYNTH/`  | 합성 스크립트 (Yosys)              |
| `GOLDEN/` | Python 비트 정확도 레퍼런스 모델   |
| `DOCS/`   | 설계 문서                          |

---

## Projects

### NPU — Weight Stationary NPU with UVM Verification

8×8 Weight Stationary Systolic Array NPU. APB 슬레이브(CPU 설정) + AXI4 마스터(DRAM DMA) 인터페이스. 완전한 UVM 검증 환경 포함.

| 항목 | 내용 |
|------|------|
| Architecture | 8×8 WS Systolic Array (64 PE, INT8 MAC) |
| Interface | APB Slave (CPU config) · AXI4 Master (DRAM DMA) |
| Memory | 256 KB on-chip SRAM (weight buffer) |
| Post-processing | ReLU + INT8 quantization (scale >> + clamp) |
| Verification | UVM Agent / Driver / Monitor / Scoreboard / Coverage |

→ [`NPU/`](./NPU/README.md)

---

### ACCEL — LLM Accelerator (Qwen 2.5-0.5B Decoder Layer)

8×8 OS Systolic Array를 Transformer Decoder Layer에 9× 시간 다중화하여 재사용. CNN과 Transformer 동일 하드웨어로 처리. UVM 검증 환경 포함.

| 항목 | 내용 |
|------|------|
| Target | Qwen 2.5-0.5B (hidden=896, GQA 14/2 heads, FFN=4864) |
| Dataflow | Output Stationary, batch=1 |
| Operators | RMSNorm · RoPE · QKV Proj · MHA · Softmax · FFN (SwiGLU) |
| Throughput | ~2.4 tok/s @ 200 MHz (sky130) |
| Synthesis | Yosys + ABC, sky130 PDK |
| Verification | UVM Agent / AXI4 BFM / Scoreboard / Coverage |

→ [`ACCEL/`](./ACCEL/DOCS/README.md)

---

### RISCV — 5-Stage Pipelined RISC-V CPU (RV32I)

완전한 RV32I 5단계 파이프라인. 데이터 포워딩, 해저드 검출, 2비트 포화 카운터 분기 예측기 포함.

| 항목 | 내용 |
|------|------|
| ISA | RISC-V RV32I (R / I / S / B / U / J 전 명령어 타입) |
| Pipeline | IF → ID → EX → MEM → WB |
| Forwarding | EX-EX and MEM-EX paths; write-first register file |
| Branch | EX-stage resolution · 1-cycle flush · 2-bit saturating predictor |
| CPI | 1.71 (predictor 없음) / ~1.45 (2-bit, loop-heavy) |
| Gate count | ~3,500 gates · sky130 target |
| Test | 22 points / 7 test cases — ALL PASS |

→ [`RISCV/`](./RISCV/README.md)

---

## Background

Samsung Electronics Foundry 6년 (Library FE DK & Verification):
SRAM 컴파일러 특성화, Liberty 타이밍 체인 분석, Fusion Compiler RTL→넷리스트 합성 및 STA,
DFT 사인오프 (JTAG / Logic BIST / Memory BIST / ATPG), Palladium/Zebu 에뮬레이션,
eFlash·eMRAM용 DNA BIST 컨트롤러 RTL 설계 (양산 적용).

본 작업물은 파운드리 물리 설계 경험을 AI 가속기 RTL로 연결한 결과물입니다.
모든 수치에는 도출 근거가 있으며, 모든 설계 결정에는 정량적 트레이드오프가 존재합니다.
