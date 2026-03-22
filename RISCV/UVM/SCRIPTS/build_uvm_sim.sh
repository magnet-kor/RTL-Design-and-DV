#!/usr/bin/env bash
# =============================================================================
# build_uvm_sim.sh — RISCV Pipeline UVM Simulation Build Script
# =============================================================================
# Usage:
#   ./build_uvm_sim.sh [TEST_NAME]
#
# Default test: riscv_regression_test
# Available tests:
#   riscv_rtype_test    - R-type ALU instructions
#   riscv_itype_test    - I-type immediate ALU
#   riscv_load_test     - Load/Store round-trip
#   riscv_branch_test   - Branch instructions
#   riscv_jal_test      - JAL jump-and-link
#   riscv_hazard_test   - Data hazard / forwarding chain
#   riscv_regression_test - Full regression (all sequences)
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UVM_DIR="${SCRIPT_DIR}/.."
RTL_DIR="${UVM_DIR}/../RTL"
UVM_STUB="${SCRIPT_DIR}/UVM_STUB"

TEST_NAME="${1:-riscv_regression_test}"
OUT="${SCRIPT_DIR}/sim_riscv_uvm"

echo "============================================"
echo "  RISCV Pipeline UVM Build"
echo "  Test: ${TEST_NAME}"
echo "============================================"

iverilog -g2012 \
  -DVERILATOR \
  -I"${UVM_STUB}" \
  "${UVM_STUB}/uvm_pkg.sv" \
  "${UVM_DIR}/AGENTS/riscv_seq_item.sv" \
  "${UVM_DIR}/AGENTS/riscv_driver.sv" \
  "${UVM_DIR}/AGENTS/riscv_monitor.sv" \
  "${UVM_DIR}/AGENTS/riscv_agent.sv" \
  "${UVM_DIR}/ENV/riscv_scoreboard.sv" \
  "${UVM_DIR}/ENV/riscv_coverage.sv" \
  "${UVM_DIR}/ENV/riscv_env.sv" \
  "${UVM_DIR}/SEQUENCES/riscv_sequences.sv" \
  "${UVM_DIR}/TESTS/riscv_tests.sv" \
  "${UVM_DIR}/TB/riscv_if.sv" \
  "${RTL_DIR}/alu.sv" \
  "${RTL_DIR}/alu_ctrl.sv" \
  "${RTL_DIR}/regfile.sv" \
  "${RTL_DIR}/imm_gen.sv" \
  "${RTL_DIR}/control.sv" \
  "${RTL_DIR}/forwarding_unit.sv" \
  "${RTL_DIR}/hdu.sv" \
  "${RTL_DIR}/branch_predictor.sv" \
  "${RTL_DIR}/riscv_pipeline.sv" \
  "${UVM_DIR}/TB/riscv_tb_top.sv" \
  -o "${OUT}"

echo "Build successful: ${OUT}"
echo "Running: vvp ${OUT} +UVM_TESTNAME=${TEST_NAME}"
vvp "${OUT}" "+UVM_TESTNAME=${TEST_NAME}"
