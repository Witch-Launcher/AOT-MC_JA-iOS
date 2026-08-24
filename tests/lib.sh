#!/usr/bin/env bash
# lib.sh — Test helpers cho AOT POC
# Usage: source "$(dirname "$0")/lib.sh" in each test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${AOT_BUILD_DIR:-$PROJECT_ROOT/build}"
LOGS_DIR="$PROJECT_ROOT/logs"
CONFIGS_DIR="${AOT_CONFIGS_DIR:-$PROJECT_ROOT/configs}"
TEST_NAME="${BASH_SOURCE[1]:-$(basename "${BASH_SOURCE[0]}")}"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

mkdir -p "$LOGS_DIR" "$BUILD_DIR"

# ── Output formatting ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
_pass()  { echo -e "${GREEN}[PASS]${NC} $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
_fail()  { echo -e "${RED}[FAIL]${NC} $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
_skip()  { echo -e "${YELLOW}[SKIP]${NC} $*"; SKIP_COUNT=$((SKIP_COUNT + 1)); }
_abort() { echo -e "${RED}[ABORT]${NC} $*"; exit 1; }

# ── Assertion helpers ──────────────────────────────────────────────
assert_file_exists() {
    local f="$1" msg="${2:-file not found: $1}"
    if [[ -f "$f" ]]; then _pass "$msg"; else _fail "$msg"; fi
}

assert_file_not_empty() {
    local f="$1" msg="${2:-file empty: $1}"
    if [[ -s "$f" ]]; then _pass "$msg"; else _fail "$msg"; fi
}

assert_dir_exists() {
    local d="$1" msg="${2:-dir not found: $1}"
    if [[ -d "$d" ]]; then _pass "$msg"; else _fail "$msg"; fi
}

assert_command_exists() {
    local cmd="$1" msg="${2:-command not found: $1}"
    if command -v "$cmd" &>/dev/null; then _pass "$msg"; else _fail "$msg"; fi
}

assert_string_in_file() {
    local pattern="$1" file="$2" msg="${3:-pattern '$1' not in $2}"
    if grep -qE "$pattern" "$file" 2>/dev/null; then _pass "$msg"; else _fail "$msg"; fi
}

assert_string_in_output() {
    local pattern="$1" output="$2" msg="${3:-pattern '$1' not in output}"
    if echo "$output" | grep -qE "$pattern"; then _pass "$msg"; else _fail "$msg"; fi
}

assert_json_valid() {
    local file="$1" msg="${2:-invalid JSON: $1}"
    if python3 -m json.tool "$file" >/dev/null 2>&1 || \
       python -m json.tool "$file" >/dev/null 2>&1; then
        _pass "$msg"
    else
        _fail "$msg"
    fi
}

assert_min_lines() {
    local file="$1" min="$2" msg="${3:-$file has fewer than $min lines}"
    local count
    count=$(wc -l < "$file" 2>/dev/null || echo 0)
    if (( count >= min )); then _pass "$msg ($count lines)"; else _fail "$msg (got $count lines)"; fi
}

assert_binary_arch() {
    local binary="$1" expected_arch="$2" msg="${3:-unexpected arch in $1}"
    local arch
    arch=$(lipo -info "$binary" 2>/dev/null | head -1 || echo "unknown")
    if echo "$arch" | grep -q "$expected_arch"; then
        _pass "$msg (found $expected_arch)"
    else
        _fail "$msg (got: $arch)"
    fi
}

assert_exit_code() {
    local expected="$1" actual="$2" msg="${3:-exit code mismatch}"
    if [[ "$actual" == "$expected" ]]; then
        _pass "$msg (exit=$actual)"
    else
        _fail "$msg (expected=$expected, got=$actual)"
    fi
}

assert_marker_in_log() {
    local marker="$1" logfile="$2" timeout="${3:-120}" msg="${4:-marker '$1' not found in log}"
    local elapsed=0
    while (( elapsed < timeout )); do
        if [[ -f "$logfile" ]] && grep -qE "$marker" "$logfile" 2>/dev/null; then
            _pass "$msg (found in ${elapsed}s)"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    _fail "$msg (timeout ${timeout}s)"
    return 1
}

# ── Test lifecycle ─────────────────────────────────────────────────
begin_test() {
    local name="$1"
    TEST_NAME="$name"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  TEST: $name${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    LOG_FILE="$LOGS_DIR/${name}.log"
    exec > >(tee -a "$LOG_FILE") 2>&1
    _info "Log: $LOG_FILE"
}

end_test() {
    echo ""
    if (( FAIL_COUNT > 0 )); then
        echo -e "${RED}TEST FAILED: $TEST_NAME (${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${SKIP_COUNT} skipped)${NC}"
        exit 1
    else
        echo -e "${GREEN}TEST PASSED: $TEST_NAME (${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${SKIP_COUNT} skipped)${NC}"
        exit 0
    fi
}

# ── Environment loader ─────────────────────────────────────────────
load_env() {
    local env_file="$PROJECT_ROOT/aot-env.sh"
    if [[ -f "$env_file" ]]; then
        source "$env_file"
        _info "Loaded environment from $env_file"
    else
        _info "No aot-env.sh found — using system defaults"
    fi
}
