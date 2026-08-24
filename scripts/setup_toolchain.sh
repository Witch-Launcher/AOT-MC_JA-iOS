#!/usr/bin/env bash
# setup_toolchain.sh — Install Maven + Gluon GraalVM for iOS native-image
# Idempotent: safe to run multiple times, checks what's already installed
# Target: macOS arm64 with Xcode

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE[0]")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$PROJECT_ROOT/build/tools"
ENV_FILE="$PROJECT_ROOT/aot-env.sh"

# ── Gluon GraalVM version (latest for Substrate 1.0.29 compatibility) ──
GLUON_GRAALVM_TAG="gluon-23+25.1-dev-2409082136"
GLUON_GRAALVM_VERSION="23+25.1-dev"
GLUON_GRAALVM_URL_DARWIN_AARCH64="https://github.com/gluonhq/graal/releases/download/${GLUON_GRAALVM_TAG}/graalvm-java23-darwin-aarch64-gluon-${GLUON_GRAALVM_VERSION}.tar.gz"
GLUON_GRAALVM_URL_DARWIN_X86_64="https://github.com/gluonhq/graal/releases/download/${GLUON_GRAALVM_TAG}/graalvm-java23-darwin-amd64-gluon-${GLUON_GRAALVM_VERSION}.tar.gz"

# ── Tools directory — use home dir if project disk is full ─────────
DISK_AVAIL_KB=$(df -k "$PROJECT_ROOT" | tail -1 | awk '{print $4}')
if (( DISK_AVAIL_KB < 2000000 )); then
    TOOLS_DIR="$HOME/aot-tools"
    echo "  Project disk low on space — storing tools at: $TOOLS_DIR"
else
    TOOLS_DIR="$PROJECT_ROOT/build/tools"
fi
mkdir -p "$TOOLS_DIR"

echo "=========================================="
echo "  AOT POC Toolchain Setup"
echo "=========================================="

# ── Step 1: Install Homebrew packages ─────────────────────────────
echo ""
echo "[1/5] Installing Homebrew packages..."

if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew not found. Install from https://brew.sh"
    exit 1
fi

# Maven
if ! command -v mvn &>/dev/null; then
    echo "Installing Maven..."
    brew install maven
else
    echo "  Maven already installed: $(mvn --version | head -1)"
fi

# Python 3 (for scripts)
if ! command -v python3 &>/dev/null; then
    echo "Installing Python 3..."
    brew install python3
else
    echo "  Python 3 already installed"
fi

# jq (for JSON processing)
if ! command -v jq &>/dev/null; then
    echo "Installing jq..."
    brew install jq
else
    echo "  jq already installed"
fi

# ── Step 2: Download Gluon GraalVM ───────────────────────────────
echo ""
echo "[2/5] Downloading Gluon GraalVM ${GLUON_GRAALVM_VERSION}..."

ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    GRAALVM_URL="$GLUON_GRAALVM_URL_DARWIN_AARCH64"
    EXPECTED_ARCH="darwin-aarch64"
elif [[ "$ARCH" == "x86_64" ]]; then
    GRAALVM_URL="$GLUON_GRAALVM_URL_DARWIN_X86_64"
    EXPECTED_ARCH="darwin-amd64"
else
    echo "ERROR: Unsupported architecture: $ARCH"
    exit 1
fi

GRAALVM_DIR="$TOOLS_DIR/graalvm-${GLUON_GRAALVM_TAG}"

# Create symlink in project build/ for convenience
mkdir -p "$PROJECT_ROOT/build"
ln -sfn "$TOOLS_DIR" "$PROJECT_ROOT/build/tools-link"

if [[ -d "$GRAALVM_DIR" ]]; then
    echo "  GraalVM already downloaded at: $GRAALVM_DIR"
else
    echo "  URL: $GRAALVM_URL"
    ARCHIVE="/tmp/graalvm-gluon.tar.gz"
    echo "  Downloading to /tmp (project disk may be full)..."
    curl -L "$GRAALVM_URL" -o "$ARCHIVE"
    echo "  Extracting..."
    tar xzf "$ARCHIVE" -C "$TOOLS_DIR/"
    rm "$ARCHIVE"

    # The archive extracts to a directory like graalvm-java23-darwin-*
    EXTRACTED=$(find "$TOOLS_DIR" -maxdepth 1 -type d -name "graalvm-java*" | head -1)
    if [[ -n "$EXTRACTED" ]]; then
        # macOS app bundle: Contents/Home/bin/java
        if [[ -d "$EXTRACTED/Contents/Home" ]]; then
            mv "$EXTRACTED" "$GRAALVM_DIR.tmp"
            mv "$GRAALVM_DIR.tmp/Contents/Home" "$GRAALVM_DIR"
            rm -rf "$GRAALVM_DIR.tmp"
        else
            mv "$EXTRACTED" "$GRAALVM_DIR"
        fi
    fi
fi

if [[ ! -d "$GRAALVM_DIR" ]]; then
    echo "ERROR: GraalVM directory not found after extraction"
    echo "Expected: $GRAALVM_DIR"
    exit 1
fi

echo "  GraalVM installed at: $GRAALVM_DIR"

# ── Step 3: Verify GraalVM ───────────────────────────────────────
echo ""
echo "[3/5] Verifying GraalVM installation..."

GRAAL_JAVA="$GRAALVM_DIR/bin/java"
GRAAL_NI="$GRAALVM_DIR/bin/native-image"

if [[ ! -x "$GRAAL_JAVA" ]]; then
    echo "ERROR: java not found at $GRAAL_JAVA"
    exit 1
fi

echo "  Java: $($GRAAL_JAVA -version 2>&1 | head -1)"

if [[ ! -x "$GRAAL_NI" ]]; then
    echo "  native-image not found, attempting to install via gu..."
    "$GRAALVM_DIR/bin/gu" install --no-progress native-image || {
        echo "ERROR: Failed to install native-image"
        exit 1
    }
fi

echo "  Native Image: $($GRAAL_NI --version 2>&1 | head -1)"

# ── Step 4: Verify Xcode + iOS SDK ───────────────────────────────
echo ""
echo "[4/5] Verifying Xcode and iOS SDK..."

if ! command -v xcodebuild &>/dev/null; then
    echo "WARNING: xcodebuild not found — iOS builds will fail"
else
    echo "  Xcode: $(xcodebuild -version | head -1)"
fi

IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
if [[ -n "$IOS_SDK" ]]; then
    echo "  iOS SDK: $IOS_SDK"
else
    echo "WARNING: iOS SDK not found"
fi

# ── Step 5: Generate environment file ─────────────────────────────
echo ""
echo "[5/5] Generating aot-env.sh..."

cat > "$ENV_FILE" <<ENVEOF
# Auto-generated by setup_toolchain.sh — do not edit manually
# Source this file: source aot-env.sh

export GRAALVM_HOME="$GRAALVM_DIR"
export PATH="\$GRAALVM_HOME/bin:\$PATH"

# Gluon Substrate settings
export GLUONFX_GRAALVM_VERSION="$GLUON_GRAALVM_TAG"

# Project paths
export AOT_PROJECT_ROOT="$PROJECT_ROOT"
export AOT_BUILD_DIR="$PROJECT_ROOT/build"
export AOT_CONFIGS_DIR="$PROJECT_ROOT/configs"
ENVEOF

echo "  Environment file: $ENV_FILE"

# ── Final summary ─────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "To use the environment, run:"
echo "  source $ENV_FILE"
echo ""
echo "To verify everything:"
echo "  bash $PROJECT_ROOT/tests/t00_toolchain.sh"
echo ""
echo "Next steps:"
echo "  1. source $ENV_FILE"
echo "  2. bash $PROJECT_ROOT/tests/t03_mc_fetch.sh"
echo "  3. bash $PROJECT_ROOT/tests/t04_agent_configs.sh"
echo ""
