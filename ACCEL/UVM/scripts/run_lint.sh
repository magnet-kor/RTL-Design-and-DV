#!/usr/bin/env bash
# =============================================================================
# run_lint.sh — Verilator Lint for UVM Environment
# =============================================================================
# Checks all UVM environment files for syntax errors using verilator
# --lint-only --bbox-unsup with a lightweight UVM 1.2 stub.
#
# Usage:
#   cd phase4/uvm
#   bash scripts/run_lint.sh
#
# Returns 0 if no errors, non-zero if errors found.
# Warnings (CONSTRAINTIGN, TIMESCALEMOD) are suppressed — expected for UVM.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UVM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STUB_DIR="$SCRIPT_DIR/uvm_stub"

echo "=============================================="
echo "  Decoder Layer UVM Environment — Lint Check"
echo "=============================================="
echo ""

# ── Validate stub directory ────────────────────────────────────────────────
if [ ! -f "$STUB_DIR/uvm_pkg.sv" ]; then
    echo "[ERROR] UVM stub not found: $STUB_DIR/uvm_pkg.sv"
    echo "        Run: bash scripts/build_uvm_stub.sh"
    exit 1
fi

# ── File list ──────────────────────────────────────────────────────────────
UVM_FILES=(
    "$STUB_DIR/uvm_pkg.sv"
    "$UVM_DIR/agents/dec_seq_item.sv"
    "$UVM_DIR/agents/dec_driver.sv"
    "$UVM_DIR/agents/dec_monitor.sv"
    "$UVM_DIR/agents/dec_agent.sv"
    "$UVM_DIR/env/dec_scoreboard.sv"
    "$UVM_DIR/env/dec_coverage.sv"
    "$UVM_DIR/env/dec_axi4_bfm.sv"
    "$UVM_DIR/env/dec_env.sv"
    "$UVM_DIR/sequences/dec_sequences.sv"
    "$UVM_DIR/tests/dec_tests.sv"
    "$UVM_DIR/tb/decoder_if.sv"
    "$UVM_DIR/tb/decoder_layer_stub.sv"
    "$UVM_DIR/tb/dec_tb_top.sv"
)

# ── Run verilator lint ─────────────────────────────────────────────────────
echo "Running: verilator --lint-only --bbox-unsup -sv"
echo "Files  : ${#UVM_FILES[@]} source files"
echo ""

LINT_OUT=$(verilator --lint-only -sv --bbox-unsup --timing \
    -I"$STUB_DIR" \
    "${UVM_FILES[@]}" 2>&1 \
    | grep -v "^%Warning-CONSTRAINTIGN" \
    | grep -v "^%Warning-TIMESCALEMOD" \
    | grep -v "^%Warning-MULTIDRIVEN" \
    | grep -v "^%Warning-UNOPTFLAT" \
    | grep -v "^%Warning-UNOPT" \
    | grep -v "^%Warning-WIDTHEXPAND" \
    | grep -v "^%Warning-WIDTHTRUNC" \
    | grep -v "^%Warning-INITIALDLY" \
    | grep -v "For warning description" \
    | grep -v "Use .* to disable" \
    | grep -v "Suggested alternative" \
    | grep -v "^\s*\.\.\." \
    | grep -v "^\s*$" \
    | grep -v "^%Error: Exiting due to" \
    || true)

# ── Report ─────────────────────────────────────────────────────────────────
ERROR_COUNT=$(echo "$LINT_OUT" | grep -c "^%Error:" || true)
WARN_COUNT=$(echo "$LINT_OUT"  | grep -c "^%Warning" || true)

if [ -n "$LINT_OUT" ]; then
    echo "$LINT_OUT"
    echo ""
fi

echo "----------------------------------------------"
echo "  Lint Result: $ERROR_COUNT error(s)  $WARN_COUNT warning(s)"
echo "----------------------------------------------"

if [ "$ERROR_COUNT" -eq 0 ]; then
    echo "  *** LINT PASS — all UVM files clean ***"
    echo "=============================================="
    exit 0
else
    echo "  *** LINT FAIL — fix errors above ***"
    echo "=============================================="
    exit 1
fi
