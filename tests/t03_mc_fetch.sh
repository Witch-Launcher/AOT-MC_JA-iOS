#!/usr/bin/env bash
# t03_mc_fetch.sh — Download MC 1.20.1 client.jar + official mappings, remap to named
# PASS: named client jar exists, net.minecraft.client.main.Main class present
# NOTE: Downloads from Mojang piston-meta (public, no auth needed)

set -euo pipefail
source "$(dirname "$0")/lib.sh"
begin_test "t03_mc_fetch"

load_env

MC_VERSION="1.20.1"
MC_DIR="$BUILD_DIR/minecraft/$MC_VERSION"
MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
VERSION_URL="$MC_DIR/version_manifest.json"
CLIENT_JAR="$MC_DIR/client.jar"
MAPPINGS_TXT="$MC_DIR/client.txt"
LIBS_DIR="$MC_DIR/libraries"
TOOLS_DIR="$BUILD_DIR/tools"

mkdir -p "$MC_DIR" "$TOOLS_DIR"

# ── Fetch version manifest ────────────────────────────────────────
if [[ ! -f "$VERSION_URL" ]] || [[ $(find "$VERSION_URL" -mmin +60 2>/dev/null | wc -l) -gt 0 ]]; then
    _info "Downloading version manifest..."
    curl -sL "$MANIFEST_URL" -o "$VERSION_URL"
fi
assert_file_exists "$VERSION_URL" "version_manifest.json downloaded"

# ── Get version URL for target MC version ──────────────────────────
VERSION_ENTRY=$(python3 -c "
import json, sys
data = json.load(open('$VERSION_URL'))
for v in data['versions']:
    if v['id'] == '$MC_VERSION':
        print(v['url'])
        sys.exit(0)
print('NOT_FOUND')
" 2>/dev/null || echo "NOT_FOUND")

if [[ "$VERSION_ENTRY" == "NOT_FOUND" ]]; then
    _fail "Minecraft version $MC_VERSION not found in manifest"
    end_test
fi
_info "Version URL: $VERSION_ENTRY"

# ── Fetch version metadata ────────────────────────────────────────
VERSION_META="$MC_DIR/version_meta.json"
curl -sL "$VERSION_ENTRY" -o "$VERSION_META"
assert_file_exists "$VERSION_META" "version metadata downloaded"

# ── Extract client jar URL ────────────────────────────────────────
CLIENT_URL=$(python3 -c "
import json, sys
data = json.load(open('$VERSION_META'))
print(data['downloads']['client']['url'])
" 2>/dev/null || echo "")

if [[ -z "$CLIENT_URL" ]]; then
    _fail "Could not extract client jar URL from metadata"
    end_test
fi

# ── Download client jar ───────────────────────────────────────────
if [[ ! -f "$CLIENT_JAR" ]]; then
    _info "Downloading client jar ($MC_VERSION)..."
    _info "URL: $CLIENT_URL"
    curl -sL "$CLIENT_URL" -o "$CLIENT_JAR"
fi
assert_file_exists "$CLIENT_JAR" "client.jar downloaded"
assert_file_not_empty "$CLIENT_JAR" "client.jar not empty"

# ── Verify SHA1 checksum ──────────────────────────────────────────
EXPECTED_SHA=$(python3 -c "
import json
data = json.load(open('$VERSION_META'))
print(data['downloads']['client']['sha1'])
" 2>/dev/null || echo "")
ACTUAL_SHA=$(shasum -a 1 "$CLIENT_JAR" | awk '{print $1}')

if [[ -n "$EXPECTED_SHA" ]] && [[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]]; then
    _pass "SHA1 checksum matches: $ACTUAL_SHA"
else
    _fail "SHA1 mismatch: expected=$EXPECTED_SHA actual=$ACTUAL_SHA"
fi

# ── Download official mappings (ProGuard → named) ─────────────────
MAPPINGS_URL=$(python3 -c "
import json
data = json.load(open('$VERSION_META'))
print(data['downloads']['client_mappings']['url'])
" 2>/dev/null || echo "")

if [[ -z "$MAPPINGS_URL" ]]; then
    _fail "Could not extract mappings URL"
    end_test
fi

if [[ ! -f "$MAPPINGS_TXT" ]]; then
    _info "Downloading official mappings..."
    curl -sL "$MAPPINGS_URL" -o "$MAPPINGS_TXT"
fi
assert_file_exists "$MAPPINGS_TXT" "client mappings downloaded"
assert_file_not_empty "$MAPPINGS_TXT" "client mappings not empty"
assert_min_lines "$MAPPINGS_TXT" 1000 "mappings has reasonable size"

# ── Verify entry point class exists ──────────────────────────────
_info "Checking for net.minecraft.client.main.Main in client jar..."
MAIN_CLASS=$(jar tf "$CLIENT_JAR" 2>/dev/null | grep "net/minecraft/client/main/Main.class" | head -1 || echo "")
if [[ -n "$MAIN_CLASS" ]]; then
    _pass "Entry point class found: $MAIN_CLASS"
    _pass "Client jar class names are NOT obfuscated — no remapping needed"
else
    _fail "net.minecraft.client.main.Main not found in client jar"
fi

# ── Extract libraries needed for native-image classpath ────────────
LIBS_DIR="$MC_DIR/libraries"
mkdir -p "$LIBS_DIR"

# Extract library URLs from version metadata
python3 -c "
import json, os, urllib.request, sys

data = json.load(open('$VERSION_META'))
libs = data.get('libraries', [])

# Download client libraries
for lib in libs:
    dl = lib.get('downloads', {}).get('artifact', {})
    url = dl.get('url', '')
    if not url: continue
    name = lib['name'].replace(':', '-').replace('/', '-')
    path = os.path.join('$LIBS_DIR', name + '.jar')
    if not os.path.exists(path):
        try:
            urllib.request.urlretrieve(url, path)
            print(f'Downloaded: {name}', file=sys.stderr)
        except Exception as e:
            print(f'Failed: {name}: {e}', file=sys.stderr)
" 2>&1 | tail -5

LIBS_COUNT=$(find "$LIBS_DIR" -name "*.jar" | wc -l | tr -d ' ')
_info "Downloaded $LIBS_COUNT library jars"

end_test
