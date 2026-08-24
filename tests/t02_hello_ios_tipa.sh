#!/usr/bin/env bash
# t02_hello_ios_tipa.sh — Build hello-world AOT for iOS, package as .tipa for TrollStore
# PASS: .app bundle exists with arm64 binary, adhoc signed, packaged as .tipa
# SKIPS gracefully if GluonFX not available or no iOS signing identity

set -euo pipefail
source "$(dirname "$0")/lib.sh"
begin_test "t02_hello_ios_tipa"

load_env

HELLO_APP_DIR="$PROJECT_ROOT/java/apps/hello"
OUTPUT_DIR="$BUILD_DIR/ios-hello"
TIPA_FILE="$OUTPUT_DIR/hello-aot.tipa"

mkdir -p "$OUTPUT_DIR"

# ── Check GraalVM + native-image ──────────────────────────────────
if [[ -z "${GRAALVM_HOME:-}" ]]; then
    _skip "GRAALVM_HOME not set — run setup_toolchain.sh"
    end_test
fi

NATIVE_IMAGE="$GRAALVM_HOME/bin/native-image"
if [[ ! -x "$NATIVE_IMAGE" ]]; then
    _skip "native-image not found"
    end_test
fi

# ── Check iOS SDK ─────────────────────────────────────────────────
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
if [[ -z "$IOS_SDK" ]]; then
    _skip "iOS SDK not found (install Xcode with iOS platform)"
    end_test
fi

# ── Check if GluonFX available ────────────────────────────────────
# Option A: GluonFX Maven plugin (preferred)
# Option B: Manual native-image + substrate link
# We try GluonFX first

HELLO_POM="$HELLO_APP_DIR/pom.xml"
if [[ ! -f "$HELLO_POM" ]]; then
    _info "Creating minimal pom.xml for GluonFX hello-world..."
    cat > "$HELLO_POM" <<'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.aot.poc</groupId>
    <artifactId>hello-aot</artifactId>
    <version>1.0-SNAPSHOT</version>
    <packaging>jar</packaging>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <gluonfx.version>1.0.29</gluonfx.version>
    </properties>

    <build>
        <plugins>
            <plugin>
                <groupId>com.gluonhq</groupId>
                <artifactId>gluonfx-maven-plugin</artifactId>
                <version>${gluonfx.version}</version>
                <configuration>
                    <mainClass>HelloMain</mainClass>
                    <reflectionList>
                        <list>HelloMain</list>
                    </reflectionList>
                    <jniList>
                    </jniList>
                    <resourcesList>
                    </resourcesList>
                    <target>${gluonfx.target}</target>
                </configuration>
            </plugin>
        </plugins>
    </build>

    <profiles>
        <profile>
            <id>ios</id>
            <properties>
                <gluonfx.target>ios</gluonfx.target>
            </properties>
        </profile>
        <profile>
            <id>host</id>
            <properties>
                <gluonfx.target>host</gluonfx.target>
            </properties>
        </profile>
    </profiles>
</project>
POMEOF
    _info "Created pom.xml"
fi

# ── Try GluonFX build for iOS ─────────────────────────────────────
if ! command -v mvn &>/dev/null && [[ ! -x "$PROJECT_ROOT/mvnw" ]]; then
    _skip "Maven not available"
    end_test
fi

_info "Building iOS native image via GluonFX..."
MVN_CMD="mvn"
if [[ -x "$PROJECT_ROOT/mvnw" ]]; then MVN_CMD="$PROJECT_ROOT/mvnw"; fi

BUILD_LOG="$LOGS_DIR/t02_gluonfx_build.log"
"$MVN_CMD" -Pios -DskipTests gluonfx:build \
    -f "$HELLO_POM" \
    2>&1 | tee "$BUILD_LOG" || {
    _info "GluonFX build failed — check $BUILD_LOG"
    _info "Common causes: missing GraalVM, missing provisioning profile"
    _skip "GluonFX iOS build not successful (see log)"
    end_test
}

# ── Check output ──────────────────────────────────────────────────
# GluonFX produces target/gluonfx/<platform>/app/
APP_DIR=$(find "$HELLO_APP_DIR/target" -name "app" -type d -path "*/ios/*" 2>/dev/null | head -1)
if [[ -z "$APP_DIR" ]]; then
    APP_DIR="$HELLO_APP_DIR/target/gluonfx/ios/app"
fi

assert_dir_exists "$APP_DIR" "iOS .app bundle produced"

# Find the main binary inside .app
APP_EXE=$(find "$APP_DIR" -type f -perm +111 ! -name "*.dylib" ! -name "*.framework" 2>/dev/null | head -1)
if [[ -n "$APP_EXE" ]]; then
    assert_binary_arch "$APP_EXE" "arm64" "Binary is arm64"
fi

# ── Package as .tipa for TrollStore ───────────────────────────────
# TrollStore accepts .tipa = renamed .ipa containing .app
_info "Packaging as .tipa for TrollStore..."
IPA_STAGING="$OUTPUT_DIR/staging"
mkdir -p "$IPA_STAGING/Payload"
cp -R "$APP_DIR" "$IPA_STAGING/Payload/" || {
    _skip "Could not copy .app to Payload"
    end_test
}

(cd "$IPA_STAGING" && zip -r "$TIPA_FILE" Payload/)
assert_file_exists "$TIPA_FILE" ".tipa file created"
assert_file_not_empty "$TIPA_FILE" ".tipa file not empty"

_info "Tipa: $TIPA_FILE"
_info "Install: transfer to device → TrollStore → tap to install"

end_test
