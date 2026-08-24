#!/usr/bin/env bash
# t04_agent_configs.sh — Run MC with native-image-agent, capture reflection/JNI/resource/proxy configs
# PASS: all 4 JSON config files exist, are valid JSON, have minimum entry counts
# NOTE: requires GraalVM + MC client jar + libraries already downloaded (t03)
# This test runs MC on the HOST JVM (not native) — takes ~30-120s

set -euo pipefail
source "$(dirname "$0")/lib.sh"
begin_test "t04_agent_configs"

load_env

MC_VERSION="1.20.1"
MC_DIR="$BUILD_DIR/minecraft/$MC_VERSION"
CLIENT_JAR="$MC_DIR/client.jar"
LIBS_DIR="$MC_DIR/libraries"
AGENT_CONFIGS="$CONFIGS_DIR/mc-$MC_VERSION"

# Minimum expected entries (conservative — headless run captures fewer)
MIN_REFLECT=5
MIN_JNI=1
MIN_RESOURCE=1
MIN_PROXY=0

mkdir -p "$AGENT_CONFIGS" "$CONFIGS_DIR"

# ── Check prerequisites ───────────────────────────────────────────
if [[ -z "${GRAALVM_HOME:-}" ]]; then
    _skip "GRAALVM_HOME not set"
    end_test
fi

if [[ ! -f "$CLIENT_JAR" ]]; then
    _skip "Client jar not found — run t03_mc_fetch.sh first"
    end_test
fi

# ── Build classpath ───────────────────────────────────────────────
CLASSPATH="$CLIENT_JAR"
for jar in "$LIBS_DIR"/*.jar; do
    CLASSPATH="$CLASSPATH:$jar"
done

# ── Run native-image-agent ────────────────────────────────────────
# The agent traces JNI, reflection, resource, proxy access during normal JVM execution
_info "Running native-image-agent on MC $MC_VERSION client..."
_info "This will take 30-120 seconds — MC will start then we'll kill it"

AGENT_LOG="$LOGS_DIR/t04_agent_run.log"

# Run MC with agent for a limited time, then kill
# Using --demo to avoid needing authentication
# On macOS, 'timeout' may not be available; use background + sleep + kill
"$GRAALVM_HOME/bin/java" \
    -agentlib:native-image-agent="config-output-dir=$AGENT_CONFIGS,config-write-period-secs=10" \
    -cp "$CLASSPATH" \
    net.minecraft.client.main.Main \
    --demo \
    --width 854 --height 480 \
    > "$AGENT_LOG" 2>&1 &
AGENT_PID=$!

# Wait up to 90 seconds, then kill
for i in $(seq 1 45); do
    if ! kill -0 "$AGENT_PID" 2>/dev/null; then
        _info "MC process exited after ${i}x2 seconds"
        break
    fi
    sleep 2
done

# Kill if still running
kill "$AGENT_PID" 2>/dev/null || true
wait "$AGENT_PID" 2>/dev/null || true
_info "Agent run completed"

# Agent writes configs periodically; final write on JVM exit (if clean)
# Force a final flush if agent didn't write yet

# ── Check reflection config ───────────────────────────────────────
REFLECT_CFG="$AGENT_CONFIGS/reflect-config.json"
assert_file_exists "$REFLECT_CFG" "reflect-config.json created"
assert_json_valid "$REFLECT_CFG" "reflect-config.json is valid JSON"
REFLECT_COUNT=$(python3 -c "
import json
data = json.load(open('$REFLECT_CFG'))
print(len(data))
" 2>/dev/null || echo 0)
if (( REFLECT_COUNT >= MIN_REFLECT )); then
    _pass "reflect-config.json has $REFLECT_COUNT entries (min $MIN_REFLECT)"
else
    _fail "reflect-config.json has only $REFLECT_COUNT entries (min $MIN_REFLECT)"
fi

# ── Check JNI config ──────────────────────────────────────────────
JNI_CFG="$AGENT_CONFIGS/jni-config.json"
assert_file_exists "$JNI_CFG" "jni-config.json created"
assert_json_valid "$JNI_CFG" "jni-config.json is valid JSON"
JNI_COUNT=$(python3 -c "
import json
data = json.load(open('$JNI_CFG'))
print(len(data))
" 2>/dev/null || echo 0)
if (( JNI_COUNT >= MIN_JNI )); then
    _pass "jni-config.json has $JNI_COUNT entries (min $MIN_JNI)"
else
    _fail "jni-config.json has only $JNI_COUNT entries (min $MIN_JNI)"
fi

# ── Check resource config ─────────────────────────────────────────
RESOURCE_CFG="$AGENT_CONFIGS/resource-config.json"
assert_file_exists "$RESOURCE_CFG" "resource-config.json created"
assert_json_valid "$RESOURCE_CFG" "resource-config.json is valid JSON"

# ── Check proxy config ────────────────────────────────────────────
PROXY_CFG="$AGENT_CONFIGS/proxy-config.json"
assert_file_exists "$PROXY_CFG" "proxy-config.json created"
assert_json_valid "$PROXY_CFG" "proxy-config.json is valid JSON"

# ── Summary ───────────────────────────────────────────────────────
_info ""
_info "=== Agent Config Summary ==="
_info "Reflection:  $REFLECT_COUNT entries"
_info "JNI:         $JNI_COUNT entries"
_info "Resource:    see $RESOURCE_CFG"
_info "Proxy:       see $PROXY_CFG"
_info ""
_info "Configs saved to: $AGENT_CONFIGS"
_info "Next step: use these configs in native-image build (t05/t06)"

end_test
