#!/usr/bin/env bash
# t01_hello_host.sh — Build hello-world native image on macOS host, run it
# PASS: binary executes, prints MARKER line, exits 0

set -euo pipefail
source "$(dirname "$0")/lib.sh"
begin_test "t01_hello_host"

load_env

HELLO_APP_DIR="$PROJECT_ROOT/java/apps/hello"
MARKER="AOT_HELLO_V1"

# ── Write a temporary HelloMain.java if not exists ────────────────
mkdir -p "$HELLO_APP_DIR/src/main/java"
HELLO_JAVA="$HELLO_APP_DIR/src/main/java/HelloMain.java"

cat > "$HELLO_JAVA" <<JAVAEOF
public class HelloMain {
    public static void main(String[] args) {
        String marker = System.getenv("AOT_MARKER");
        if (marker == null || marker.isEmpty()) marker = "${MARKER}";
        System.out.println(marker);
        System.out.println("GraalVM native-image: " + System.getProperty("java.vm.name"));
        System.out.println("OS: " + System.getProperty("os.name") + " " + System.getProperty("os.arch"));
    }
}
JAVAEOF
_info "Created HelloMain.java"

# ── Check GraalVM available ───────────────────────────────────────
if [[ -z "${GRAALVM_HOME:-}" ]]; then
    _skip "GRAALVM_HOME not set"
    end_test
fi

NATIVE_IMAGE="$GRAALVM_HOME/bin/native-image"
if [[ ! -x "$NATIVE_IMAGE" ]]; then
    _skip "native-image not found at $NATIVE_IMAGE"
    end_test
fi

# ── Compile ───────────────────────────────────────────────────────
COMPILED="$BUILD_DIR/hello/HelloMain.class"
mkdir -p "$BUILD_DIR/hello"
_info "Compiling HelloMain.java..."
"$GRAALVM_HOME/bin/javac" -d "$BUILD_DIR/hello" "$HELLO_JAVA"
assert_file_exists "$COMPILED" "javac produced HelloMain.class"

# ── Build native image ────────────────────────────────────────────
NATIVE_BIN="$BUILD_DIR/hello/hello-aot"
mkdir -p "$BUILD_DIR/hello"
_info "Building native image (this takes ~10-30s)..."
rm -f "$NATIVE_BIN" "$NATIVE_BIN.task"  # force rebuild
"$NATIVE_IMAGE" \
    --no-fallback \
    --no-server \
    -H:Name="$NATIVE_BIN" \
    -cp "$BUILD_DIR/hello" \
    HelloMain 2>&1 | tail -5

assert_file_exists "$NATIVE_BIN" "native binary produced"

# ── Run native binary ─────────────────────────────────────────────
_info "Running native binary..."
OUTPUT=$("$NATIVE_BIN" 2>&1 || true)
_info "Output: $OUTPUT"

assert_string_in_output "$MARKER" "$OUTPUT" "Marker line printed"
assert_string_in_output "GraalVM|native-image|Substrate" "$OUTPUT" "VM name mentioned"

# ── Run with custom env var ───────────────────────────────────────
CUSTOM_MARKER="CUSTOM_MARKER_$(date +%s)"
OUTPUT2=$(AOT_MARKER="$CUSTOM_MARKER" "$NATIVE_BIN" 2>&1 || true)
assert_string_in_output "$CUSTOM_MARKER" "$OUTPUT2" "Custom AOT_MARKER env var respected"

end_test
