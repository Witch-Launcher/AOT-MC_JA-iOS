#!/usr/bin/env bash
# capture_agent.sh — Run MC client with native-image-agent to capture reflection/JNI/resource/proxy configs
# Runs MC on HOST JVM for ~90s, then extracts agent-generated configs
# Multiple scenarios recommended: menu, world load, options, multiplayer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE[0]")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/tests/lib.sh"

MC_VERSION="${1:-1.20.1}"
MC_DIR="$BUILD_DIR/minecraft/$MC_VERSION"
CLIENT_JAR="$MC_DIR/client.jar"
LIBS_DIR="$MC_DIR/libraries"
CONFIGS_OUT="$CONFIGS_DIR/mc-$MC_VERSION"
RUN_SECONDS="${2:-90}"

mkdir -p "$CONFIGS_OUT"

if [[ -z "${GRAALVM_HOME:-}" ]]; then
    _abort "GRAALVM_HOME not set"
fi

if [[ ! -f "$CLIENT_NAMED" ]]; then
    _abort "Remapped jar not found — run remap_client.sh first"
fi

# ── Build classpath ───────────────────────────────────────────────
CLASSPATH="$CLIENT_JAR"
for jar in "$LIBS_DIR"/*.jar; do
    CLASSPATH="$CLASSPATH:$jar"
done

# ── Run agent ─────────────────────────────────────────────────────
_info "Running MC $MC_VERSION with native-image-agent for ${RUN_SECONDS}s..."
_info "This opens a real MC window — interact with it to capture more reflection paths!"
_info ""
_info "Suggested interactions during capture:"
_info "  - Let title screen fully load"
_info "  - Click Options → Video Settings"
_info "  - Click Singleplayer → create/load a world"
_info "  - If possible: open chat, inventory"
_info ""

timeout "$RUN_SECONDS" "$GRAALVM_HOME/bin/java" \
    -agentlib:native-image-agent="\
config-output-dir=$CONFIGS_OUT,\
config-write-period-secs=10" \
    -cp "$CLASSPATH" \
    net.minecraft.client.main.Main \
    --demo \
    2>&1 | tail -20 || true

# ── Verify outputs ────────────────────────────────────────────────
_info ""
_info "Agent configs generated in: $CONFIGS_OUT"

for f in reflect-config.json jni-config.json resource-config.json proxy-config.json; do
    FILE="$CONFIGS_OUT/$f"
    if [[ -f "$FILE" ]]; then
        COUNT=$(python3 -c "import json; print(len(json.load(open('$FILE'))))" 2>/dev/null || echo "?")
        _pass "$f: $COUNT entries"
    else
        _fail "$f: not found"
    fi
done

_info ""
_info "To capture more reflection paths, run this script again and interact with different MC features."
_info "Configs are MERGED across runs, so each run adds more coverage."
