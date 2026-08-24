#!/usr/bin/env bash
# build_ios_tipa.sh — Cross-compile MC for iOS via GluonFX/Substrate, package as .tipa
# Usage: ./build_ios_tipa.sh [version]
# Note: requires Xcode + iOS SDK + Gluon GraalVM + provisioning profile

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE[0]")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/tests/lib.sh"

MC_VERSION="${1:-1.20.1}"
MC_DIR="$BUILD_DIR/minecraft/$MC_VERSION"
CLIENT_JAR="$MC_DIR/client.jar"
LIBS_DIR="$MC_DIR/libraries"
OUTPUT_DIR="$BUILD_DIR/ios"
APP_NAME="Witch-AOT"
TIPA_FILE="$OUTPUT_DIR/${APP_NAME}.tipa"
APP_BUNDLE="$OUTPUT_DIR/${APP_NAME}.app"

mkdir -p "$OUTPUT_DIR"

if [[ -z "${GRAALVM_HOME:-}" ]]; then
    _abort "GRAALVM_HOME not set"
fi

# ── Check iOS SDK ─────────────────────────────────────────────────
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
if [[ -z "$IOS_SDK" ]]; then
    _abort "iOS SDK not found"
fi

# ── Build classpath ───────────────────────────────────────────────
CLASSPATH="$CLIENT_JAR"
for jar in "$LIBS_DIR"/*.jar; do
    CLASSPATH="$CLASSPATH:$jar"
done

# ── Agent configs ─────────────────────────────────────────────────
AGENT_CONFIGS="$CONFIGS_DIR/mc-$MC_VERSION"
CONFIG_FLAG=""
if [[ -d "$AGENT_CONFIGS" ]]; then
    CONFIG_FLAG="-H:ConfigurationFileDirectories=$AGENT_CONFIGS"
fi

# ── Strategy: Use GluonFX Maven plugin or manual substrate ────────
# GluonFX approach (preferred):
# Create a wrapper Maven project that depends on the MC jar

IOS_POM="$OUTPUT_DIR/pom.xml"
if [[ ! -f "$IOS_POM" ]]; then
    _info "Creating iOS build POM..."
    cat > "$IOS_POM" <<POMEOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.aot.poc</groupId>
    <artifactId>minecraft-aot-ios</artifactId>
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
                <version>\${gluonfx.version}</version>
                <configuration>
                    <mainClass>net.minecraft.client.main.Main</mainClass>
                    <reflectionList>
                        <list>net.minecraft.client.main.Main</list>
                        <list>net.minecraft.client.Minecraft</list>
                    </reflectionList>
                    <target>ios</target>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
POMEOF
fi

# ── Build with GluonFX ────────────────────────────────────────────
_info "Building iOS native image via GluonFX..."
_info "This is the most complex step — may require multiple iterations"

# Option 1: Try Maven GluonFX plugin
if command -v mvn &>/dev/null; then
    _info "Using Maven GluonFX plugin..."
    mvn -Pios gluonfx:build \
        -f "$IOS_POM" \
        -DskipTests \
        2>&1 | tee "$LOGS_DIR/ios_build.log" || {
        _info "Maven build failed — attempting manual substrate approach"
    }
fi

# Option 2: Manual native-image + substrate (fallback)
# This directly invokes native-image with iOS target flags
_info "Attempting manual native-image for iOS..."

"$GRAALVM_HOME/bin/native-image" \
    --no-fallback \
    --no-server \
    --report-unsupported-elements-at-runtime \
    --enable-url-protocols=http,https \
    --initialize-at-run-time=io.netty \
    --initialize-at-build-time=net.minecraft.util.profiling.jfr.event \
    -R:MaxHeapSize=3g \
    -H:+AllowVMInspection \
    -H:+AddAllCharsets \
    -H:IncludeResources="assets/.*|data/.*|META-INF/.*" \
    $CONFIG_FLAG \
    -H:Name="$OUTPUT_DIR/minecraft-client" \
    -cp "$CLASSPATH" \
    net.minecraft.client.main.Main \
    2>&1 | tee "$LOGS_DIR/ios_build_manual.log" || {
    _fail "iOS build failed — check logs"
    _info "Common issues:"
    _info "  1. Missing provisioning profile (set iosSignIdentity in POM)"
    _info "  2. LWJGL dylibs not linked (check jni-config.json)"
    _info "  3. MetalANGLE framework not in classpath"
    exit 1
}

# ── Package as .tipa ──────────────────────────────────────────────
_info "Packaging as .tipa for TrollStore..."

# Create .app bundle structure
mkdir -p "$APP_BUNDLE"
cp "$OUTPUT_DIR/minecraft-client" "$APP_BUNDLE/$APP_NAME" 2>/dev/null || \
    cp "$OUTPUT_DIR/minecraft-client" "$APP_BUNDLE/" 2>/dev/null || true

# Copy necessary frameworks and dylibs
DYLIBS_DIR="$PROJECT_ROOT/../Natives/resources/Frameworks"
if [[ -d "$DYLIBS_DIR" ]]; then
    _info "Bundling native libraries from repo..."
    cp "$DYLIBS_DIR"/*.dylib "$APP_BUNDLE/" 2>/dev/null || true
    mkdir -p "$APP_BUNDLE/Frameworks"
    cp -R "$DYLIBS_DIR"/*.framework "$APP_BUNDLE/Frameworks/" 2>/dev/null || true
fi

# Bundle assets
ASSETS_DIR="$MC_DIR/assets"
if [[ -d "$ASSETS_DIR" ]]; then
    _info "Bundling game assets..."
    cp -R "$ASSETS_DIR" "$APP_BUNDLE/assets/"
fi

# Bundle client config/data
cp -R "$MC_DIR/data" "$APP_BUNDLE/" 2>/dev/null || true
cp -R "$MC_DIR/libraries" "$APP_BUNDLE/" 2>/dev/null || true

# Create Info.plist
cat > "$APP_BUNDLE/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.aot.minecraft.poc</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>MinimumOSVersion</key>
    <string>15.0</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
</dict>
</plist>
PLIST

# Package as .ipa/.tipa
STAGING="$OUTPUT_DIR/staging"
mkdir -p "$STAGING/Payload"
cp -R "$APP_BUNDLE" "$STAGING/Payload/"

(cd "$STAGING" && zip -r -q "$TIPA_FILE" Payload/)

_assert_file_exists "$TIPA_FILE" ".tipa created"
_info ""
_info "Tipa file: $TIPA_FILE"
_info "Size: $(du -h "$TIPA_FILE" | cut -f1)"
_info ""
_info "To install on device:"
_info "  1. Transfer $TIPA_FILE to iPhone"
_info "  2. Open in TrollStore"
_info "  3. App will install as 'Witch-AOT'"
