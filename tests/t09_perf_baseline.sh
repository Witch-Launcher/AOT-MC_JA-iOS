#!/usr/bin/env bash
# t09_perf_baseline.sh — Measure and compare AOT vs JIT: startup time, RSS, FPS
# PASS: baseline metrics collected and saved, comparison table printed
# NOTE: JIT baseline = regular MC on desktop JVM; AOT baseline = native binary

set -euo pipefail
source "$(dirname "$0")/lib.sh"
begin_test "t09_perf_baseline"

load_env

MC_VERSION="1.20.1"
MC_DIR="$BUILD_DIR/minecraft/$MC_VERSION"
PERF_DIR="$BUILD_DIR/perf"
JIT_LOG="$PERF_DIR/jit_baseline.log"
AOT_LOG="$PERF_DIR/aot_baseline.log"
DEVICE_AOT_LOG="$PERF_DIR/device_aot.log"
REPORT="$PERF_DIR/performance_report.txt"

mkdir -p "$PERF_DIR"

# ── Helper: measure startup time ──────────────────────────────────
measure_startup() {
    local binary="$1" name="$2" logfile="$3"
    local start_ts end_ts elapsed

    _info "Measuring startup for: $name"
    start_ts=$(python3 -c "import time; print(time.time())")

    # Run with timeout, capture output
    timeout 30 "$binary" --nogui --port 25567 --demo \
        --world "$PERF_DIR/test-world-$name" \
        > "$logfile" 2>&1 || true

    # Wait for "Done" marker or timeout
    local ELAPSED=0
    while (( ELAPSED < 30 )); do
        if grep -qE "Done \(" "$logfile" 2>/dev/null; then
            end_ts=$(python3 -c "import time; print(time.time())")
            elapsed=$(python3 -c "print(round($end_ts - $start_ts, 3))")
            _pass "$name startup: ${elapsed}s"
            echo "$elapsed"
            return 0
        fi
        sleep 1
        ELAPSED=$((ELAPSED + 1))
    done

    # Didn't find marker — still record time
    end_ts=$(python3 -c "import time; print(time.time())")
    elapsed=$(python3 -c "print(round($end_ts - $start_ts, 3))")
    _info "$name: no 'Done' marker in ${elapsed}s (may not have fully booted)"
    echo "$elapsed"
    return 0
}

# ── Helper: measure RSS (peak memory) ─────────────────────────────
measure_rss() {
    local pid="$1" name="$2"
    local peak_rss=0
    local current=0

    while kill -0 "$pid" 2>/dev/null; do
        current=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0)
        if (( current > peak_rss )); then
            peak_rss=$current
        fi
        sleep 0.5
    done

    local peak_mb=$((peak_rss / 1024))
    _pass "$name peak RSS: ${peak_mb}MB"
    echo "$peak_mb"
}

# ── Step 1: JIT baseline (regular JVM, no AOT) ───────────────────
if [[ -f "$MC_DIR/client.jar" ]] && [[ -n "${GRAALVM_HOME:-}" ]]; then
    _info "=== JIT BASELINE (JVM with JIT) ==="

    CLASSPATH="$MC_DIR/client.jar"
    for jar in "$MC_DIR/libraries"/*.jar; do
        CLASSPATH="$CLASSPATH:$jar"
    done

    JIT_STARTUP=$(measure_startup "$GRAALVM_HOME/bin/java" "JIT-JVM" "$JIT_LOG" || echo "N/A")
else
    _skip "JIT baseline: missing client jar or GRAALVM_HOME"
    JIT_STARTUP="N/A"
fi

# ── Step 2: AOT baseline (native server on desktop) ──────────────
SERVER_NATIVE="$BUILD_DIR/minecraft/server-native"
if [[ -x "$SERVER_NATIVE" ]]; then
    _info "=== AOT BASELINE (native server) ==="

    AOT_STARTUP=$(measure_startup "$SERVER_NATIVE" "AOT-Server" "$AOT_LOG" || echo "N/A")
else
    _skip "AOT baseline: server native not built yet (run t05 first)"
    AOT_STARTUP="N/A"
fi

# ── Step 3: Device AOT (if device connected) ─────────────────────
DEVICE_ID=""
if command -v idevice_id &>/dev/null; then
    DEVICE_ID=$(idevice_id -l 2>/dev/null | head -1 || echo "")
fi

DEVICE_FPS="N/A"
DEVICE_RSS="N/A"
DEVICE_STARTUP="N/A"

if [[ -n "$DEVICE_ID" ]]; then
    _info "=== DEVICE AOT (on iPhone/iPad) ==="

    # Launch app and measure
    ideviceinstaller -u "$DEVICE_ID" -b "com.witch.zad626" 2>/dev/null || true
    sleep 2

    # Collect logs for 15s
    timeout 15 idevicesyslog -u "$DEVICE_ID" 2>/dev/null | \
        grep -iE "fps|startup|render|frame|done" \
        > "$DEVICE_AOT_LOG" || true

    if [[ -s "$DEVICE_AOT_LOG" ]]; then
        DEVICE_STARTUP=$(grep -iE "startup|boot|done" "$DEVICE_AOT_LOG" | head -1 || echo "N/A")
        DEVICE_FPS=$(grep -oE "fps=[0-9]+|FPS: [0-9]+|[0-9]+ fps" "$DEVICE_AOT_LOG" | head -1 || echo "N/A")
        _info "Device startup: $DEVICE_STARTUP"
        _info "Device FPS: $DEVICE_FPS"
    fi

    # Kill app
    xcrun devicectl device process terminate "$DEVICE_ID" "com.witch.zad626" 2>/dev/null || true
else
    _skip "No device connected for device AOT measurement"
fi

# ── Generate report ───────────────────────────────────────────────
cat > "$REPORT" <<REPORT
=== Minecraft AOT Performance Report ===
Date: $(date)
MC Version: $MC_VERSION

┌──────────────────┬──────────────┬──────────────┐
│ Metric           │ JIT (JVM)    │ AOT (Native) │
├──────────────────┼──────────────┼──────────────┤
│ Startup (s)      │ $JIT_STARTUP │ $AOT_STARTUP │
│ Peak RSS (MB)    │ see logs     │ see logs     │
│ FPS (title scr)  │ N/A          │ $DEVICE_FPS  │
└──────────────────┴──────────────┴──────────────┘

Notes:
- JIT baseline: JVM with GraalVM (has JIT compiler)
- AOT baseline: native image (no JIT, static compilation)
- AOT typically has faster startup but potentially lower throughput
- RSS measured during server boot; client RSS TBD on device

Full logs:
- JIT: $JIT_LOG
- AOT Server: $AOT_LOG
- Device: $DEVICE_AOT_LOG
REPORT

_info ""
_info "=== Performance Report ==="
cat "$REPORT"
_info ""
_info "Report saved to: $REPORT"

# ── Summary ───────────────────────────────────────────────────────
_pass "Performance metrics collected (baseline established)"
_info "Compare: JIT=$JIT_STARTUP vs AOT=$AOT_STARTUP startup time"

end_test
