#!/usr/bin/env bash
# remap_client.sh — Remap MC client jar from obfuscated → named using official mappings
# Requires: tiny-remapper (downloaded automatically if missing)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE[0]")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/tests/lib.sh"

MC_VERSION="${1:-1.20.1}"
MC_DIR="$BUILD_DIR/minecraft/$MC_VERSION"
TOOLS_DIR="$BUILD_DIR/tools"
TINY_REMAPPER="$TOOLS_DIR/tiny-remapper.jar"

mkdir -p "$TOOLS_DIR"

# ── Download tiny-remapper if needed ──────────────────────────────
if [[ ! -f "$TINY_REMAPPER" ]]; then
    _info "Downloading tiny-remapper..."
    curl -sL "https://maven.fabricmc.net/net/fabricmc/tiny-remapper/0.9.0/tiny-remapper-0.9.0-fat.jar" \
        -o "$TINY_REMAPPER"
fi

# ── Remap ─────────────────────────────────────────────────────────
_info "Remapping $MC_VERSION client jar (obf → named)..."
java -jar "$TINY_REMAPPER" \
    "$MC_DIR/client.jar" \
    "$MC_DIR/client.txt" \
    -o "$MC_DIR/client-named.jar" \
    2>&1

_info "Output: $MC_DIR/client-named.jar"

# ── Verify ────────────────────────────────────────────────────────
MAIN_CLASS=$(jar tf "$MC_DIR/client-named.jar" 2>/dev/null | grep "net/minecraft/client/main/Main.class" || echo "")
if [[ -n "$MAIN_CLASS" ]]; then
    _pass "Entry point found: $MAIN_CLASS"
else
    _fail "net.minecraft.client.main.Main not found in remapped jar"
    jar tf "$MC_DIR/client-named.jar" | grep -i "main" | head -10 || true
fi
