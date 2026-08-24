#!/usr/bin/env bash
# t00_toolchain.sh — Validate GraalVM + Maven + Xcode + Substrate toolchain
# PASS: all required tools present and compatible versions
# SKIP: if GRAALVM_HOME not set (user hasn't run setup yet)

set -euo pipefail
source "$(dirname "$0")/lib.sh"
begin_test "t00_toolchain"

load_env

# ── Check GRAALVM_HOME ────────────────────────────────────────────
if [[ -z "${GRAALVM_HOME:-}" ]]; then
    _skip "GRAALVM_HOME not set — run scripts/setup_toolchain.sh first"
    _skip "(remaining checks skipped)"
    end_test
fi

assert_dir_exists "$GRAALVM_HOME" "GRAALVM_HOME directory exists"

# ── Check native-image ────────────────────────────────────────────
NATIVE_IMAGE="$GRAALVM_HOME/bin/native-image"
if [[ -x "$NATIVE_IMAGE" ]] || [[ -f "$NATIVE_IMAGE" ]]; then
    _pass "native-image binary exists"
    NI_VERSION=$("$NATIVE_IMAGE" --version 2>&1 || echo "unknown")
    _info "native-image version: $NI_VERSION"
else
    _fail "native-image not found at $NATIVE_IMAGE"
fi

# ── Check Java version in GraalVM ─────────────────────────────────
GRAAL_JAVA="$GRAALVM_HOME/bin/java"
if [[ -x "$GRAAL_JAVA" ]]; then
    JAVA_VER=$("$GRAAL_JAVA" -version 2>&1 | head -1)
    _info "GraalVM Java: $JAVA_VER"
    if echo "$JAVA_VER" | grep -qE '(17|21|22|23|24|25)'; then
        _pass "Java version is 17+"
    else
        _fail "Java version not in supported range (17-25): $JAVA_VER"
    fi
else
    _fail "GraalVM java binary not found at $GRAAL_JAVA"
fi

# ── Check Maven ───────────────────────────────────────────────────
if command -v mvn &>/dev/null; then
    MVN_VER=$(mvn --version 2>&1 | head -1)
    _pass "Maven installed: $MVN_VER"
elif [[ -x "$PROJECT_ROOT/mvnw" ]]; then
    _pass "Maven wrapper found at mvnw"
else
    _fail "Maven not found (install: brew install maven)"
fi

# ── Check Xcode command line tools ────────────────────────────────
if command -v xcodebuild &>/dev/null; then
    XCODE_VER=$(xcodebuild -version 2>&1 | head -1)
    _pass "Xcode: $XCODE_VER"
else
    _fail "xcodebuild not found"
fi

# ── Check Xcode SDK for iOS ───────────────────────────────────────
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
if [[ -n "$IOS_SDK" ]] && [[ -d "$IOS_SDK" ]]; then
    _pass "iOS SDK found: $IOS_SDK"
else
    _fail "iOS SDK not found"
fi

# ── Check for Gluon Substrate static Java libs ────────────────────
# Substrate downloads these during build; check if already cached
STATIC_LIBS_DIR="$HOME/.gluon/substrate/svm"
if [[ -d "$STATIC_LIBS_DIR" ]]; then
    _pass "Gluon static libs cache exists: $STATIC_LIBS_DIR"
    ls -d "$STATIC_LIBS_DIR"/*/ 2>/dev/null | head -5 | while read d; do
        _info "  $(basename "$d")"
    done
else
    _info "Gluon static libs cache not yet created (will be downloaded on first build)"
    _pass "Static libs cache will be created automatically"
fi

# ── Check available disk space (need ~8GB for MC native image build) ─
# Check both project disk and home dir tools disk
DISK_AVAIL=$(df -g "$HOME" | tail -1 | awk '{print $4}')
if (( DISK_AVAIL >= 8 )); then
    _pass "Disk space: ${DISK_AVAIL}GB available on home (need ≥8GB)"
else
    _fail "Disk space: ${DISK_AVAIL}GB available (need ≥8GB)"
fi

# ── Check architecture ────────────────────────────────────────────
ARCH=$(uname -m)
_info "Host architecture: $ARCH"
if [[ "$ARCH" == "arm64" ]]; then
    _pass "Apple Silicon (arm64) — can cross-compile for iOS arm64"
elif [[ "$ARCH" == "x86_64" ]]; then
    _info "Intel Mac — iOS builds may require Rosetta or cross-compilation caveats"
    _pass "x86_64 host (proceed with caution)"
else
    _fail "Unexpected architecture: $ARCH"
fi

end_test
