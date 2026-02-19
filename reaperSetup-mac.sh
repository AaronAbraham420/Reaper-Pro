#!/bin/bash
# ============================================================
#  REAPER Setup Script for macOS
#  Installs: SWS Extension + ReaPack Package Manager
# ============================================================

set -e

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()    { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()     { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo -e "\n${BOLD}============================================${NC}"
echo -e "${BOLD}   REAPER Dependency Installer for macOS   ${NC}"
echo -e "${BOLD}============================================${NC}\n"

# ── Check REAPER is installed ────────────────────────────────
REAPER_APP="/Applications/REAPER.app"
REAPER_RESOURCE="$HOME/Library/Application Support/REAPER"
REAPER_PLUGINS="$REAPER_RESOURCE/UserPlugins"

if [ ! -d "$REAPER_APP" ]; then
  warn "REAPER not found at $REAPER_APP"
  warn "Make sure REAPER is installed before running this script."
  read -rp "Continue anyway? (y/N): " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

mkdir -p "$REAPER_PLUGINS"
ok "UserPlugins folder ready: $REAPER_PLUGINS"

TMPDIR_CUSTOM=$(mktemp -d)
trap 'rm -rf "$TMPDIR_CUSTOM"' EXIT

# ============================================================
#  1. SWS EXTENSION
# ============================================================
echo -e "\n${BOLD}── Installing SWS Extension ──────────────────${NC}"

SWS_API="https://api.github.com/repos/reaper-oss/sws/releases/latest"

log "Fetching latest SWS release info..."
SWS_RELEASE=$(curl -fsSL "$SWS_API") || error "Could not reach GitHub API."

# ── Show all available assets so you can see what's there ───
echo -e "\n${YELLOW}Available release assets:${NC}"
echo "$SWS_RELEASE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f\"  Tag: {data.get('tag_name', 'unknown')}\")
for a in data.get('assets', []):
    print(f\"  -> {a['name']}\")
"

# ── Extract macOS installer URL (pkg or dmg) ─────────────────
SWS_URL=$(echo "$SWS_RELEASE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assets = data.get('assets', [])

# Prefer .pkg, fall back to .dmg
for ext in ('.pkg', '.dmg'):
    for a in assets:
        name = a['name'].lower()
        if name.endswith(ext) and ('mac' in name or 'osx' in name or 'darwin' in name or ext == '.pkg'):
            print(a['browser_download_url'])
            sys.exit(0)

# Last resort: any .pkg or .dmg
for a in assets:
    name = a['name'].lower()
    if name.endswith('.pkg') or name.endswith('.dmg'):
        print(a['browser_download_url'])
        sys.exit(0)
" 2>/dev/null)

SWS_VERSION=$(echo "$SWS_RELEASE" | python3 -c "
import sys, json
print(json.load(sys.stdin).get('tag_name', 'unknown'))
")

if [ -z "$SWS_URL" ]; then
  error "Could not find a .pkg or .dmg for SWS $SWS_VERSION above.\nCheck https://github.com/reaper-oss/sws/releases manually."
fi

# Detect file type
EXT="${SWS_URL##*.}"
SWS_FILE="$TMPDIR_CUSTOM/sws.$EXT"

log "Found SWS $SWS_VERSION ($EXT) -> $SWS_URL"
log "Downloading..."
curl -L --progress-bar "$SWS_URL" -o "$SWS_FILE" || error "SWS download failed."

if [ "$EXT" = "pkg" ]; then
  log "Installing .pkg (requires admin password)..."
  sudo installer -pkg "$SWS_FILE" -target / || error "SWS pkg installation failed."

elif [ "$EXT" = "dmg" ]; then
  log "Mounting .dmg..."
  MOUNT_POINT=$(mktemp -d)
  hdiutil attach "$SWS_FILE" -mountpoint "$MOUNT_POINT" -quiet

  # Find the .pkg or .dylib inside the dmg
  INNER_PKG=$(find "$MOUNT_POINT" -name "*.pkg" | head -1)
  INNER_LIB=$(find "$MOUNT_POINT" -name "*.dylib" | head -1)

  if [ -n "$INNER_PKG" ]; then
    log "Found .pkg inside dmg, installing..."
    sudo installer -pkg "$INNER_PKG" -target / || error "SWS inner pkg install failed."
  elif [ -n "$INNER_LIB" ]; then
    log "Found .dylib inside dmg, copying to UserPlugins..."
    cp "$INNER_LIB" "$REAPER_PLUGINS/"
  else
    hdiutil detach "$MOUNT_POINT" -quiet
    error "Could not find a .pkg or .dylib inside the SWS dmg."
  fi

  hdiutil detach "$MOUNT_POINT" -quiet
fi

ok "SWS $SWS_VERSION installed successfully!"

# ============================================================
#  2. REAPACK
# ============================================================
echo -e "\n${BOLD}-- Installing ReaPack ---------------------${NC}"

REAPACK_URL="https://reapack.com/files/reaper_reapack.dylib"
REAPACK_DEST="$REAPER_PLUGINS/reaper_reapack.dylib"

if [ -f "$REAPACK_DEST" ]; then
  warn "ReaPack already exists at $REAPACK_DEST"
  read -rp "Overwrite with latest version? (y/N): " overwrite
  if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
    ok "Skipped ReaPack update."
  else
    log "Downloading ReaPack..."
    curl -L --progress-bar "$REAPACK_URL" -o "$REAPACK_DEST" || error "ReaPack download failed."
    ok "ReaPack updated."
  fi
else
  log "Downloading ReaPack..."
  curl -L --progress-bar "$REAPACK_URL" -o "$REAPACK_DEST" || error "ReaPack download failed."
  ok "ReaPack installed to $REAPACK_DEST"
fi

log "Clearing quarantine flag..."
xattr -dr com.apple.quarantine "$REAPACK_DEST" 2>/dev/null || true
ok "Quarantine cleared."

# ============================================================
#  DONE
# ============================================================
echo -e "\n${BOLD}============================================${NC}"
echo -e "${GREEN}${BOLD}   All done! Here's what was installed:${NC}"
echo -e "   SWS Extension  $SWS_VERSION"
echo -e "   ReaPack        (latest)"
echo -e "${BOLD}============================================${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "  1. Open REAPER"
echo -e "  2. Go to Extensions -> ReaPack -> Synchronize packages"
echo -e "  3. Enjoy!\n"