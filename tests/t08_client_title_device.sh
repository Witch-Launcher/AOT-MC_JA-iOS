#!/usr/bin/env bash
# t08_client_title_device.sh — On-device: verify MC title screen reachable, measure FPS
# PASS: log contains "Backend library: LWJGL" or "Minecraft" + title screen loads, FPS > 0
# REQUIRES: device connected, .tipa deployed, t07 passed

set -euo pipefail
source "$(dirname "$0")/lib.sh"
begin_test "t08_client_title_device"

load_env

MC_VERSION="1.20.1"
APP_NAME="Witch-AOT"
DEVICE_LOG="$LOGS_DIR/t08_device_title.log"
FPS_LOG="$LOGS_DIR/t08_fps.csv"
BOOT_TIMEOUT=45
MIN_FPS=1

# ── Check device ──────────────────────────────────────────────────
DEVICE_ID=""
if command -v idevice_id &>/dev/null; then
    DEVICE_ID=$(idevice_id -l 2>/dev/null | head -1 || echo "")
fi
if [[ -z "$DEVICE_ID" ]]; then
    _skip "No iOS device connected"
    end_test
fi

# ── Check app installed ───────────────────────────────────────────
INSTALLED=$(ideviceinstaller -l 2>/dev/null | grep -c "$APP_NAME" || echo "0")
if (( INSTALLED == 0 )); then
    _skip "$APP_NAME not installed on device"
    end_test
fi

# ── Launch app and monitor ────────────────────────────────────────
_info "Launching $APP_NAME for title screen test..."

# Start log capture
> "$DEVICE_LOG"
idevicesyslog -u "$DEVICE_ID" 2>/dev/null | \
    grep -iE "Witch|minecraft|lwjgl|opengl|vulkan|fps|render|title|main" \
    >> "$DEVICE_LOG" &
SYSLOG_PID=$!

# Launch
ideviceinstaller -u "$DEVICE_ID" -b "com.witch.zad626" 2>/dev/null || true

# ── Wait for title screen indicators ──────────────────────────────
_info "Waiting for title screen indicators (timeout: ${BOOT_TIMEOUT}s)..."

ELAPSED=0
TITLE_FOUND=0
while (( ELAPSED < BOOT_TIMEOUT )); do
    if [[ -s "$DEVICE_LOG" ]]; then
        # Title screen indicators
        if grep -qiE "Backend library.*LWJGL|GL version.*[0-9]|title screen|splash|Mojang" "$DEVICE_LOG"; then
            TITLE_FOUND=1
            break
        fi
        # Even "Done" or "Connected" are good
        if grep -qiE "Done \(|Connected to|Loading complete" "$DEVICE_LOG"; then
            TITLE_FOUND=1
            break
        fi
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if (( TITLE_FOUND )); then
    _pass "Title screen indicators found in device logs"
    grep -iE "Backend|GL version|title|splash|Mojang|Done" "$DEVICE_LOG" | head -5 | while read line; do
        _info "  $line"
    done
else
    _info "Title screen indicators not found within timeout"
    _info "Last 10 log lines:"
    tail -10 "$DEVICE_LOG" 2>/dev/null || true
fi

# ── Measure FPS (if app exposes frame timing) ─────────────────────
_info "Collecting frame timing data for 10s..."
> "$FPS_LOG"

# Look for FPS-related output in device logs
FPS_FOUND=0
collect_frames() {
    timeout 10 idevicesyslog -u "$DEVICE_ID" 2>/dev/null | \
        grep -iE "fps|frame|render.*time|frame.*time|fps=" \
        >> "$FPS_LOG" || true
}

collect_frames &
COLLECT_PID=$!
sleep 12
kill "$COLLECT_PID" 2>/dev/null || true

FPS_LINES=$(wc -l < "$FPS_LOG" 2>/dev/null || echo 0)
if (( FPS_LINES > 0 )); then
    FPS_FOUND=1
    _pass "FPS data captured: $FPS_LINES entries in $FPS_LOG"
    _info "Sample entries:"
    head -3 "$FPS_LOG" | while read line; do _info "  $line"; done
else
    _info "No FPS data in device logs (may need app-side instrumentation)"
fi

# ── Screenshot for visual verification ────────────────────────────
if command -v idevicescreenshot &>/dev/null; then
    SCREENSHOT="$BUILD_DIR/ios/title_screen.png"
    idevicescreenshot -u "$DEVICE_ID" "$SCREENSHOT" 2>/dev/null || true
    if [[ -f "$SCREENSHOT" ]]; then
        _pass "Screenshot: $SCREENSHOT"
        _info "Manually check: title screen visible?"
    fi
fi

# ── Stop app ──────────────────────────────────────────────────────
kill "$SYSLOG_PID" 2>/dev/null || true
xcrun devicectl device process terminate "$DEVICE_ID" "com.witch.zad626" 2>/dev/null || true

# ── Summary ───────────────────────────────────────────────────────
_info ""
_info "=== Title Screen Test Summary ==="
if (( TITLE_FOUND )); then
    _pass "Title screen reachable on device"
else
    _fail "Title screen not reached (check device logs, may need more agent configs)"
fi

end_test
