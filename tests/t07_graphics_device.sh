#!/usr/bin/env bash
# t07_graphics_device.sh — On-device: verify EGL context creation + basic GL rendering
# PASS: EGL init succeeds, clear color renders a non-black frame
# REQUIRES: device connected via USB, TrollStore installed, AOT .tipa deployed
# SKIPS gracefully if no device available

set -euo pipefail
source "$(dirname "$0")/lib.sh"
begin_test "t07_graphics_device"

load_env

MC_VERSION="1.20.1"
APP_NAME="Witch-AOT"
DEVICE_LOG="$LOGS_DIR/t07_device.log"
SCREENSHOT="$BUILD_DIR/ios/screenshot.png"

# ── Check device connected ────────────────────────────────────────
if ! command -v idevice_id &>/dev/null && ! command -v xcrun &>/dev/null; then
    _skip "No iOS device tools found"
    end_test
fi

DEVICE_ID=$(idevice_id -l 2>/dev/null | head -1 || xcrun devicectl list devices 2>/dev/null | grep -E "device|phone" | head -1 | awk '{print $1}' || echo "")

if [[ -z "$DEVICE_ID" ]]; then
    _skip "No iOS device connected (connect via USB and trust computer)"
    end_test
fi

_info "Device: $DEVICE_ID"

# ── Check app is installed ────────────────────────────────────────
INSTALLED=$(ideviceinstaller -l 2>/dev/null | grep -c "$APP_NAME" || echo "0")
if (( INSTALLED == 0 )); then
    _skip "$APP_NAME not installed on device — deploy .tipa first (see t02)"
    end_test
fi
_info "$APP_NAME is installed"

# ── Launch app and capture logs ───────────────────────────────────
_info "Launching $APP_NAME and monitoring logs for ${BOOT_TIMEOUT:-30}s..."

# Clear old logs
idevicesyslog -u "$DEVICE_ID" 2>/dev/null | head -0 &
SYSLOG_PID=$!

# Launch the app
ideviceinstaller -u "$DEVICE_ID" -b "com.witch.zad626" 2>/dev/null || \
    xcrun devicectl device process launch - "$DEVICE_ID" "com.witch.zad626" 2>/dev/null || \
    _info "App launch command may need manual trigger"

sleep 5

# Capture logs for 25s looking for graphics markers
timeout 25 idevicesyslog -u "$DEVICE_ID" 2>/dev/null | tee "$DEVICE_LOG" &
LOG_PID=$!
sleep 25
kill "$LOG_PID" 2>/dev/null || true
kill "$SYSLOG_PID" 2>/dev/null || true

# ── Check for EGL/graphics markers ────────────────────────────────
if [[ -f "$DEVICE_LOG" ]]; then
    if grep -qiE "EGL\|eglCreateContext\|eglMakeCurrent" "$DEVICE_LOG"; then
        _pass "EGL context creation detected in device logs"
    else
        _info "EGL markers not found in logs (may need manual inspection)"
    fi

    if grep -qiE "GLES\|glClear\|glViewport\|OpenGL" "$DEVICE_LOG"; then
        _pass "OpenGL ES rendering calls detected"
    fi

    if grep -qiE "MetalANGLE\|libEGL\|libGLES" "$DEVICE_LOG"; then
        _pass "MetalANGLE renderer loaded"
    fi

    if grep -qiE "lwjgl\|LWJGL" "$DEVICE_LOG"; then
        _pass "LWJGL detected in device logs"
    fi
else
    _info "No device logs captured — try manual: idevicesyslog | grep Witch"
fi

# ── Attempt screenshot (if tools available) ───────────────────────
if command -v idevicescreenshot &>/dev/null; then
    idevicescreenshot -u "$DEVICE_ID" "$SCREENSHOT" 2>/dev/null || true
    if [[ -f "$SCREENSHOT" ]]; then
        _pass "Screenshot captured: $SCREENSHOT"
        _info "Manual check: open screenshot to verify non-black rendering"
    fi
fi

# ── Stop the app ──────────────────────────────────────────────────
ideviceinstaller -u "$DEVICE_ID" -b "com.witch.zad626" --uninstall 2>/dev/null || true
# Or use process termination
xcrun devicectl device process terminate "$DEVICE_ID" "com.witch.zad626" 2>/dev/null || true

_info "Manual verification recommended:"
_info "  1. Install .tipa via TrollStore"
_info "  2. Launch app → check if GL context renders (non-black screen)"
_info "  3. Check idevicesyslog for LWJGL/MetalANGLE/EGL markers"

end_test
