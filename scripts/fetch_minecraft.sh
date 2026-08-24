#!/usr/bin/env bash
# fetch_minecraft.sh — Download MC 1.20.1 client + server jars, official mappings
# Reusable script (test t03 calls this)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE[0]")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/tests/lib.sh"

MC_VERSION="${1:-1.20.1}"
MC_DIR="$BUILD_DIR/minecraft/$MC_VERSION"
MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"

mkdir -p "$MC_DIR"

_info "Fetching Minecraft $MC_VERSION..."

# Version manifest
curl -sL "$MANIFEST_URL" -o "$MC_DIR/version_manifest.json"

# Version metadata
VERSION_URL=$(python3 -c "
import json
data = json.load(open('$MC_DIR/version_manifest.json'))
for v in data['versions']:
    if v['id'] == '$MC_VERSION':
        print(v['url'])
        break
")
curl -sL "$VERSION_URL" -o "$MC_DIR/version_meta.json"

# Client jar
CLIENT_URL=$(python3 -c "
import json
data = json.load(open('$MC_DIR/version_meta.json'))
print(data['downloads']['client']['url'])
")
if [[ ! -f "$MC_DIR/client.jar" ]]; then
    _info "Downloading client.jar..."
    curl -sL "$CLIENT_URL" -o "$MC_DIR/client.jar"
fi

# Server jar
SERVER_URL=$(python3 -c "
import json
data = json.load(open('$MC_DIR/version_meta.json'))
print(data['downloads']['server']['url'])
")
if [[ ! -f "$MC_DIR/server.jar" ]]; then
    _info "Downloading server.jar..."
    curl -sL "$SERVER_URL" -o "$MC_DIR/server.jar"
fi

# Official mappings
MAPPINGS_URL=$(python3 -c "
import json
data = json.load(open('$MC_DIR/version_meta.json'))
print(data['downloads']['client_mappings']['url'])
")
if [[ ! -f "$MC_DIR/client.txt" ]]; then
    _info "Downloading official mappings..."
    curl -sL "$MAPPINGS_URL" -o "$MC_DIR/client.txt"
fi

# Libraries
LIBS_DIR="$MC_DIR/libraries"
mkdir -p "$LIBS_DIR"
python3 -c "
import json, os, urllib.request, sys
data = json.load(open('$MC_DIR/version_meta.json'))
for lib in data.get('libraries', []):
    dl = lib.get('downloads', {}).get('artifact', {})
    url = dl.get('url', '')
    if not url: continue
    name = lib['name'].replace(':', '-').replace('/', '-')
    path = os.path.join('$LIBS_DIR', name + '.jar')
    if not os.path.exists(path):
        try:
            urllib.request.urlretrieve(url, path)
            print(f'  Downloaded: {name}')
        except Exception as e:
            print(f'  Failed: {name}: {e}', file=sys.stderr)
" 2>&1 | tail -10

_info "Done. Files in $MC_DIR:"
ls -lh "$MC_DIR"/*.jar "$MC_DIR"/*.txt 2>/dev/null | while read line; do
    _info "  $line"
done
