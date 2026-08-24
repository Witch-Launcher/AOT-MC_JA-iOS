#!/usr/bin/env bash
# run_all_tests.sh — Run all AOT POC tests in sequence
# Usage: bash tests/run_all_tests.sh [t00|t01|...|t09|all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE[0]")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TESTS_DIR="$PROJECT_ROOT/tests"
LOGS_DIR="$PROJECT_ROOT/logs"

mkdir -p "$LOGS_DIR"

TARGET="${1:-all}"

TESTS=(
    "t00_toolchain"
    "t01_hello_host"
    "t02_hello_ios_tipa"
    "t03_mc_fetch"
    "t04_agent_configs"
    "t05_server_native"
    "t06_client_native_desktop"
    "t07_graphics_device"
    "t08_client_title_device"
    "t09_perf_baseline"
)

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

echo "=========================================="
echo "  AOT POC Test Suite"
echo "=========================================="
echo ""

for test in "${TESTS[@]}"; do
    if [[ "$TARGET" != "all" ]] && [[ "$test" != "$TARGET" ]]; then
        continue
    fi

    TEST_SCRIPT="$TESTS_DIR/${test}.sh"
    if [[ ! -f "$TEST_SCRIPT" ]]; then
        echo "[SKIP] $test — script not found"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    TOTAL=$((TOTAL + 1))
    echo ""
    echo "── Running: $test ─────────────────────────────"

    if bash "$TEST_SCRIPT"; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=========================================="
echo "  SUMMARY: $PASSED/$TOTAL passed, $FAILED failed, $SKIPPED skipped"
echo "=========================================="

if (( FAILED > 0 )); then
    echo "Logs: $LOGS_DIR/"
    exit 1
else
    echo "All tests passed!"
    exit 0
fi
