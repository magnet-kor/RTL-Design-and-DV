#!/usr/bin/env bash
# =============================================================================
# sim/run.sh — Build and run RISC-V pipeline simulation
# =============================================================================
# Usage:
#   bash run.sh          # run testbench, print results
#   bash run.sh wave     # also open GTKWave
# =============================================================================
set -e
cd "$(dirname "$0")"

RTL=../rtl
TB=../tb
OUT=./out

mkdir -p "$OUT"

echo "[1/2] Compiling..."
iverilog -g2012 -Wall \
    "$RTL/alu.sv"              \
    "$RTL/regfile.sv"          \
    "$RTL/imm_gen.sv"          \
    "$RTL/alu_ctrl.sv"         \
    "$RTL/control.sv"          \
    "$RTL/forwarding_unit.sv"  \
    "$RTL/hdu.sv"              \
    "$RTL/branch_predictor.sv" \
    "$RTL/riscv_pipeline.sv"   \
    "$TB/riscv_pipeline_tb.sv" \
    -o "$OUT/sim"

echo "[2/2] Running..."
cd "$OUT"
./sim

if [ "$1" = "wave" ]; then
    echo "Opening GTKWave..."
    gtkwave riscv_pipeline.vcd &
fi
