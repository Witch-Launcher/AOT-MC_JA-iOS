#!/usr/bin/env bash
# build_native_desktop.sh — Build MC native image for desktop (macOS) for testing
# Usage: ./build_native_desktop.sh [server|client] [version]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE[0]")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/tests/lib.sh"

MODE="${1:-server}"
MC_VERSION="${2:-1.20.1}"
MC_DIR="$BUILD_DIR/minecraft/$MC_VERSION"

# Use client-specific configs if building client, otherwise server configs
if [[ "$MODE" == "client" ]]; then
    AGENT_CONFIGS="$CONFIGS_DIR/mc-${MC_VERSION}-client"
else
    AGENT_CONFIGS="$CONFIGS_DIR/mc-$MC_VERSION"
fi
OUTPUT="$BUILD_DIR/minecraft/${MODE}-native"

if [[ -z "${GRAALVM_HOME:-}" ]]; then
    _abort "GRAALVM_HOME not set"
fi

NATIVE_IMAGE="$GRAALVM_HOME/bin/native-image"

# ── Determine main class and jar ──────────────────────────────────
if [[ "$MODE" == "server" ]]; then
    MAIN_CLASS="net.minecraft.server.Main"
    # For 1.20.1+, server.jar is a bundler — extract the actual server jar
    BUNDLED="$MC_DIR/server.jar"
    EXTRACTED="$MC_DIR/server-extracted.jar"
    if [[ ! -f "$EXTRACTED" ]]; then
        _info "Extracting server from bundler jar..."
        mkdir -p "$MC_DIR/bundler-extract"
        (cd "$MC_DIR/bundler-extract" && unzip -o "$BUNDLED" META-INF/versions/*/server-*.jar 2>/dev/null)
        EXTRACTED_JAR=$(find "$MC_DIR/bundler-extract" -name "server-*.jar" | head -1)
        if [[ -n "$EXTRACTED_JAR" ]]; then
            mv "$EXTRACTED_JAR" "$EXTRACTED"
            rm -rf "$MC_DIR/bundler-extract"
        fi
    fi
    JAR="$EXTRACTED"
    MAX_HEAP="4g"
elif [[ "$MODE" == "client" ]]; then
    MAIN_CLASS="net.minecraft.client.main.Main"
    JAR="$MC_DIR/client.jar"
    MAX_HEAP="3g"
else
    _abort "Unknown mode: $MODE (use 'server' or 'client')"
fi

if [[ ! -f "$JAR" ]]; then
    _abort "Jar not found: $JAR — run fetch_minecraft.sh first"
fi

# ── Build classpath ───────────────────────────────────────────────
CLASSPATH="$JAR"
for jar in "$MC_DIR/libraries"/*.jar; do
    CLASSPATH="$CLASSPATH:$jar"
done
# Add config dir for log4j2.xml
if [[ -d "$MC_DIR/config" ]]; then
    CLASSPATH="$CLASSPATH:$MC_DIR/config"
fi

# ── Config directories ────────────────────────────────────────────
CONFIG_FLAG=""
if [[ -d "$AGENT_CONFIGS" ]]; then
    CONFIG_FLAG="-H:ConfigurationFileDirectories=$AGENT_CONFIGS"
fi

# ── Build native image ────────────────────────────────────────────
_info "Building $MODE native image for $MC_VERSION..."
_info "Output: $OUTPUT"
_info "This may take 20-90 minutes depending on classpath size"

BUILD_LOG="$LOGS_DIR/build_${MODE}_${MC_VERSION}.log"

"$NATIVE_IMAGE" \
    --no-fallback \
    --report-unsupported-elements-at-runtime \
    --enable-url-protocols=http,https \
    --initialize-at-run-time=io.netty \
    --initialize-at-build-time=net.minecraft.util.profiling.jfr.event,org.apache.logging.log4j,org.apache.logging.slf4j,com.mojang.logging \
    -R:MaxHeapSize="$MAX_HEAP" \
    -H:+UnlockExperimentalVMOptions \
    -H:+AllowVMInspection \
    -H:+AddAllCharsets \
    -H:IncludeResources="assets/.*|data/.*|META-INF/.*|log4j2.xml" \
    $CONFIG_FLAG \
    -H:Name="$OUTPUT" \
    -cp "$CLASSPATH" \
    "$MAIN_CLASS" \
    2>&1 | tee "$BUILD_LOG" || {
    _fail "Build failed — see $BUILD_LOG"
    exit 1
}

_pass "Native image built: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
