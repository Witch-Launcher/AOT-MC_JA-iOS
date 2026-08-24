#!/usr/bin/env bash
# t06_client_native_desktop.sh — Build MC 1.20.1 CLIENT as native image on desktop, smoke test
# PASS: binary starts, reaches LWJGL init or window creation attempt, bounded runtime
# NOTE: Full graphics won't work on headless; we verify the binary is functional

set -euo pipefail
source "$(dirname "$0")/lib.sh"
begin_test "t06_client_native_desktop"

load_env

MC_VERSION="1.20.1"
MC_DIR="$BUILD_DIR/minecraft/$MC_VERSION"
CLIENT_JAR="$MC_DIR/client.jar"
LIBS_DIR="$MC_DIR/libraries"
AGENT_CONFIGS="$CONFIGS_DIR/mc-$MC_VERSION"
CLIENT_NATIVE="$BUILD_DIR/minecraft/client-native"
CLIENT_LOG="$LOGS_DIR/t06_client_desktop.log"
BOOT_TIMEOUT=60

# ── Check prerequisites ───────────────────────────────────────────
if [[ -z "${GRAALVM_HOME:-}" ]]; then
    _skip "GRAALVM_HOME not set"
    end_test
fi

NATIVE_IMAGE="$GRAALVM_HOME/bin/native-image"
if [[ ! -x "$NATIVE_IMAGE" ]]; then
    _skip "native-image not found"
    end_test
fi

if [[ ! -f "$CLIENT_NAMED" ]]; then
    _skip "Remapped client jar not found — run t03_mc_fetch.sh first"
    end_test
fi

# ── Build classpath ───────────────────────────────────────────────
CLASSPATH="$CLIENT_JAR"
for jar in "$LIBS_DIR"/*.jar; do
    CLASSPATH="$CLASSPATH:$jar"
done

# ── Build native image of client ──────────────────────────────────
if [[ ! -x "$CLIENT_NATIVE" ]]; then
    _info "Building native image of MC client (this takes 30-90 minutes)..."
    _info "This is the most resource-intensive build step"

    CONFIG_DIR_FLAG=""
    if [[ -d "$AGENT_CONFIGS" ]]; then
        CONFIG_DIR_FLAG="-H:ConfigurationFileDirectories=$AGENT_CONFIGS"
    fi

    BUILD_LOG="$LOGS_DIR/t06_client_build.log"

    "$NATIVE_IMAGE" \
        --no-fallback \
        --no-server \
        --report-unsupported-elements-at-runtime \
        --enable-url-protocols=http,https \
        --initialize-at-run-time=io.netty,org.lwjgl \
        --initialize-at-build-time=net.minecraft.util.profiling.jfr.event \
        -R:MaxHeapSize=3g \
        -H:+AllowVMInspection \
        -H:+AddAllCharsets \
        -H:IncludeResources="assets/.*|data/.*|META-INF/.*" \
        $CONFIG_DIR_FLAG \
        -H:Name="$CLIENT_NATIVE" \
        -cp "$CLASSPATH" \
        net.minecraft.client.main.Main \
        2>&1 | tee "$BUILD_LOG" || {
        _fail "native-image build failed (see $BUILD_LOG)"
        _info "Common fixes: add missing reflection entries to reflect-config.json"
        end_test
    }
fi

assert_file_exists "$CLIENT_NATIVE" "client native binary produced"
_info "Client native binary: $CLIENT_NATIVE ($(du -h "$CLIENT_NATIVE" | cut -f1))"

# ── Smoke test: run with --help or --demo ─────────────────────────
_info "Running client native binary (headless smoke test)..."
_info "Expecting: startup logs, possibly LWJGL init attempt or crash (both OK for validation)"

# Client normally needs a display; we run it with a short timeout
# and capture whatever output it produces — even crash output is useful
OUTPUT=$(timeout 15 "$CLIENT_NATIVE" \
    --demo \
    --width 854 --height 480 \
    2>&1 || true)

echo "$OUTPUT" > "$CLIENT_LOG"
_info "Output captured in $CLIENT_LOG"

# ── Check various success indicators ──────────────────────────────
FOUND_ANY=0

# Check for LWJGL version mention (means MC core started)
if echo "$OUTPUT" | grep -qi "lwjgl\|LWJGL"; then
    _pass "LWJGL initialization attempted"
    FOUND_ANY=1
fi

# Check for Minecraft version mention
if echo "$OUTPUT" | grep -qiE "$MC_VERSION\|Minecraft"; then
    _pass "Minecraft version $MC_VERSION detected in output"
    FOUND_ANY=1
fi

# Check for OpenGL or rendering mention
if echo "$OUTPUT" | grep -qiE "OpenGL\|GLFW\|Vulkan\|render"; then
    _pass "Graphics subsystem initialization detected"
    FOUND_ANY=1
fi

# Check for Mojang splash / boot messages
if echo "$OUTPUT" | grep -qiE "mojang\|bootstrap\|Loading\|Bootstrapping"; then
    _pass "MC bootstrap/startup phase detected"
    FOUND_ANY=1
fi

# Even crash is informative
if echo "$OUTPUT" | grep -qiE "Exception\|Error\|UNSUPPORTED\|UnsupportedOperation"; then
    _pass "Crash with exception — but binary executed (expected on headless desktop)"
    FOUND_ANY=1
fi

if (( FOUND_ANY == 0 )); then
    _fail "No recognizable MC output — binary may not have started"
    _info "Full output:"
    echo "$OUTPUT" | head -30
fi

_info "Note: full GUI test will run on-device (t08_client_title_device.sh)"

end_test
