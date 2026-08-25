#!/usr/bin/env bash
# build_native_desktop.sh — Build MC native image for desktop (macOS)
# Usage: ./build_native_desktop.sh [server|client] [version]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE[0]")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/tests/lib.sh"

MODE="${1:-server}"
MC_VERSION="${2:-1.20.1}"
MC_DIR="$BUILD_DIR/minecraft/$MC_VERSION"

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

if [[ "$MODE" == "server" ]]; then
    MAIN_CLASS="net.minecraft.server.Main"
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
    MAX_HEAP="3g"
elif [[ "$MODE" == "client" ]]; then
    MAIN_CLASS="net.minecraft.client.main.Main"
    JAR="$MC_DIR/client.jar"
    MAX_HEAP="2g"
else
    _abort "Unknown mode: $MODE"
fi

if [[ ! -f "$JAR" ]]; then
    _abort "Jar not found: $JAR"
fi

CLASSPATH="$JAR"
for jar in "$MC_DIR/libraries"/*.jar; do
    CLASSPATH="$CLASSPATH:$jar"
done
if [[ -d "$MC_DIR/config" ]]; then
    CLASSPATH="$CLASSPATH:$MC_DIR/config"
fi

CONFIG_FLAG=""
if [[ -d "$AGENT_CONFIGS" ]]; then
    CONFIG_FLAG="-H:ConfigurationFileDirectories=$AGENT_CONFIGS"
fi

_info "Building $MODE native image for $MC_VERSION..."
_info "Output: $OUTPUT"
_info "CP entries: $(echo "$CLASSPATH" | tr ':' '\n' | wc -l) jars"

BUILD_LOG="$LOGS_DIR/build_${MODE}_${MC_VERSION}.log"

"$NATIVE_IMAGE" \
    --no-fallback \
    -O0 \
    -J-Xmx6g \
    --enable-url-protocols=http,https \
    --initialize-at-run-time=io.netty,com.mojang.authlib,com.mojang.logging \
    --initialize-at-build-time=net.minecraft.util.profiling.jfr.event,org.apache.logging.log4j,org.apache.logging.slf4j \
    -R:MaxHeapSize="$MAX_HEAP" \
    -H:+UnlockExperimentalVMOptions \
    -H:DeadlockWatchdogInterval=600 \
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
