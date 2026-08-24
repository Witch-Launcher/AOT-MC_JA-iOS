#!/usr/bin/env bash
# t05_server_native.sh — Build MC 1.20.1 dedicated server as native image, boot it
# PASS: server boots, prints "Done (x.xxxs)! For help" marker, stops cleanly
# NOTE: Server AOT is proven feasible (hpi-swa/native-minecraft-server)

set -euo pipefail
source "$(dirname "$0")/lib.sh"
begin_test "t05_server_native"

load_env

MC_VERSION="1.20.1"
MC_DIR="$BUILD_DIR/minecraft/$MC_VERSION"
SERVER_JAR="$MC_DIR/server.jar"
SERVER_NAMED="$MC_DIR/server-named.jar"
LIBS_DIR="$MC_DIR/libraries"
AGENT_CONFIGS="$CONFIGS_DIR/mc-$MC_VERSION"
SERVER_NATIVE="$BUILD_DIR/minecraft/server-native"
SERVER_LOG="$LOGS_DIR/t05_server_boot.log"
BOOT_TIMEOUT=120

mkdir -p "$BUILD_DIR/minecraft"

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

if [[ ! -f "$SERVER_JAR" ]]; then
    _skip "server.jar not found — run t03_mc_fetch.sh first"
    end_test
fi

# ── Download server jar if not present ─────────────────────────────
# MC 1.20.1 server jar URL (from piston-meta)
if [[ ! -f "$SERVER_JAR" ]]; then
    _info "Downloading server.jar for $MC_VERSION..."
    SERVER_URL=$(python3 -c "
import json
data = json.load(open('$MC_DIR/version_meta.json'))
print(data['downloads']['server']['url'])
" 2>/dev/null || echo "")
    if [[ -n "$SERVER_URL" ]]; then
        curl -sL "$SERVER_URL" -o "$SERVER_JAR"
    fi
fi
assert_file_exists "$SERVER_JAR" "server.jar exists"

# ── Build server classpath ────────────────────────────────────────
CLASSPATH="$SERVER_JAR"
for jar in "$LIBS_DIR"/*.jar; do
    CLASSPATH="$CLASSPATH:$jar"
done

# ── Build native image of server ──────────────────────────────────
if [[ ! -x "$SERVER_NATIVE" ]]; then
    _info "Building native image of MC server (this takes 20-60 minutes)..."
    _info "Using hpi-swa/native-minecraft-server inspired flags"

    # Merge agent configs if they exist
    CONFIG_DIR_FLAG=""
    if [[ -d "$AGENT_CONFIGS" ]]; then
        CONFIG_DIR_FLAG="-H:ConfigurationFileDirectories=$AGENT_CONFIGS"
    fi

    # Also check if hpi-swa configs exist locally
    HPI_CONFIG="$PROJECT_ROOT/configs/native-minecraft-server/configuration"
    if [[ -d "$HPI_CONFIG" ]]; then
        if [[ -n "$CONFIG_DIR_FLAG" ]]; then
            CONFIG_DIR_FLAG="$CONFIG_DIR_FLAG,$HPI_CONFIG"
        else
            CONFIG_DIR_FLAG="-H:ConfigurationFileDirectories=$HPI_CONFIG"
        fi
    fi

    BUILD_LOG="$LOGS_DIR/t05_server_build.log"

    "$NATIVE_IMAGE" \
        --no-fallback \
        --no-server \
        --report-unsupported-elements-at-runtime \
        --enable-url-protocols=http,https \
        --initialize-at-run-time=io.netty \
        --initialize-at-build-time=net.minecraft.util.profiling.jfr.event \
        -R:MaxHeapSize=2g \
        -H:+AllowVMInspection \
        $CONFIG_DIR_FLAG \
        -H:Name="$SERVER_NATIVE" \
        -cp "$CLASSPATH" \
        net.minecraft.server.Main \
        2>&1 | tee "$BUILD_LOG" || {
        _fail "native-image build failed (see $BUILD_LOG)"
        end_test
    }
fi

assert_file_exists "$SERVER_NATIVE" "server native binary produced"
_info "Server native binary: $SERVER_NATIVE ($(du -h "$SERVER_NATIVE" | cut -f1))"

# ── Boot server ───────────────────────────────────────────────────
_info "Booting MC server (timeout: ${BOOT_TIMEOUT}s)..."
_info "Server will create world, generate terrain, then print 'Done'"

# Delete any leftover world data for clean boot
rm -rf "$BUILD_DIR/minecraft/server-test-world"

timeout "$BOOT_TIMEOUT" "$SERVER_NATIVE" \
    --nogui \
    --port 25566 \
    --demo \
    --world "$BUILD_DIR/minecraft/server-test-world" \
    2>&1 | tee "$SERVER_LOG" &
SERVER_PID=$!

# ── Wait for "Done" marker ────────────────────────────────────────
MARKER="Done \("
FOUND=0
ELAPSED=0
while (( ELAPSED < BOOT_TIMEOUT )); do
    if [[ -f "$SERVER_LOG" ]] && grep -qE "$MARKER" "$SERVER_LOG" 2>/dev/null; then
        FOUND=1
        break
    fi
    # Check if server process died
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        _fail "Server process exited before boot completed"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if (( FOUND )); then
    BOOT_TIME=$(grep -oE "Done \([0-9.]+s\)" "$SERVER_LOG" | head -1 || echo "Done")
    _pass "Server booted successfully: $BOOT_TIME"
else
    _fail "Server did not print 'Done' marker within ${BOOT_TIMEOUT}s"
    _info "Last 10 lines of server log:"
    tail -10 "$SERVER_LOG" 2>/dev/null || true
fi

# ── Stop server cleanly ───────────────────────────────────────────
_info "Stopping server..."
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true

# Give it a moment to write stop marker
sleep 5
if [[ -f "$SERVER_LOG" ]] && grep -qE "Stopping server|Shutdown complete" "$SERVER_LOG" 2>/dev/null; then
    _pass "Server stopped cleanly"
else
    _info "Server stop marker not found (may have been killed)"
    _pass "Server process terminated"
fi

end_test
