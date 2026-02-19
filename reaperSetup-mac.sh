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

# ── Detect architecture ──────────────────────────────────────
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
  log "Detected Apple Silicon (arm64)"
  SWS_ARCH_KEYWORDS=("aarch64" "arm64")
else
  log "Detected Intel x86_64"
  SWS_ARCH_KEYWORDS=("x86_64" "x64" "intel")
fi

# ── Check REAPER is installed ────────────────────────────────
REAPER_APP="/Applications/REAPER.app"
REAPER_RESOURCE="$HOME/Library/Application Support/REAPER"
REAPER_PLUGINS="$REAPER_RESOURCE/UserPlugins"

if [ ! -d "$REAPER_APP" ]; then
  warn "REAPER not found at $REAPER_APP"
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

SWS_VERSION=$(echo "$SWS_RELEASE" | python3 -c "
import sys, json
print(json.load(sys.stdin).get('tag_name', 'unknown'))
")

# ── Show all available assets ────────────────────────────────
echo -e "\n${YELLOW}Available release assets for $SWS_VERSION:${NC}"
echo "$SWS_RELEASE" | python3 -c "
import sys, json
for a in json.load(sys.stdin).get('assets', []):
    print(f\"  -> {a['name']}\")
"

# ── Find the right macOS .dylib for this architecture ────────
SWS_URL=$(echo "$SWS_RELEASE" | python3 -c "
import sys, json
import os

data = json.load(sys.stdin)
assets = data.get('assets', [])
arch = os.environ.get('ARCH', 'x86_64')

arch_keywords = ['aarch64', 'arm64'] if arch == 'arm64' else ['x86_64', 'x64', 'intel']

# Priority 1: arch-specific macOS .dylib
for a in assets:
    name = a['name'].lower()
    if name.endswith('.dylib'):
        for kw in arch_keywords:
            if kw in name:
                print(a['browser_download_url'])
                sys.exit(0)

# Priority 2: any .dylib (might be universal)
for a in assets:
    name = a['name'].lower()
    if name.endswith('.dylib'):
        print(a['browser_download_url'])
        sys.exit(0)

# Priority 3: .pkg or .dmg (older releases)
for ext in ('.pkg', '.dmg'):
    for a in assets:
        if a['name'].lower().endswith(ext):
            print(a['browser_download_url'])
            sys.exit(0)
" 2>/dev/null)

if [ -z "$SWS_URL" ]; then
  error "Could not find a macOS asset for SWS $SWS_VERSION.\nSee the asset list above and check https://github.com/reaper-oss/sws/releases"
fi

EXT="${SWS_URL##*.}"
SWS_FILE="$TMPDIR_CUSTOM/sws.$EXT"

log "Downloading: $(basename $SWS_URL)"
curl -L --progress-bar "$SWS_URL" -o "$SWS_FILE" || error "SWS download failed."

# ── Install based on file type ───────────────────────────────
if [ "$EXT" = "dylib" ]; then
  # New-style: copy directly into UserPlugins
  DEST_NAME=$(basename "$SWS_URL")
  cp "$SWS_FILE" "$REAPER_PLUGINS/$DEST_NAME"
  log "Clearing quarantine flag on SWS..."
  xattr -dr com.apple.quarantine "$REAPER_PLUGINS/$DEST_NAME" 2>/dev/null || true
  ok "SWS $SWS_VERSION installed to UserPlugins/$DEST_NAME"

elif [ "$EXT" = "pkg" ]; then
  log "Installing .pkg (requires admin password)..."
  sudo installer -pkg "$SWS_FILE" -target / || error "SWS pkg installation failed."
  ok "SWS $SWS_VERSION installed."

elif [ "$EXT" = "dmg" ]; then
  log "Mounting .dmg..."
  MOUNT_POINT=$(mktemp -d)
  hdiutil attach "$SWS_FILE" -mountpoint "$MOUNT_POINT" -quiet

  INNER_PKG=$(find "$MOUNT_POINT" -name "*.pkg" | head -1)
  INNER_LIB=$(find "$MOUNT_POINT" -name "*.dylib" | head -1)

  if [ -n "$INNER_PKG" ]; then
    sudo installer -pkg "$INNER_PKG" -target / || error "SWS inner pkg install failed."
  elif [ -n "$INNER_LIB" ]; then
    cp "$INNER_LIB" "$REAPER_PLUGINS/"
    xattr -dr com.apple.quarantine "$REAPER_PLUGINS/$(basename $INNER_LIB)" 2>/dev/null || true
  else
    hdiutil detach "$MOUNT_POINT" -quiet
    error "Could not find a usable file inside the SWS dmg."
  fi

  hdiutil detach "$MOUNT_POINT" -quiet
  ok "SWS $SWS_VERSION installed."
fi

# ============================================================
#  2. REAPACK
# ============================================================
echo -e "\n${BOLD}── Installing ReaPack ────────────────────────${NC}"

REAPACK_URL="https://reapack.com/files/reaper_reapack.dylib"
REAPACK_DEST="$REAPER_PLUGINS/reaper_reapack.dylib"

if [ -f "$REAPACK_DEST" ]; then
  warn "ReaPack already exists at $REAPACK_DEST"
  read -rp "Overwrite with latest version? (y/N): " overwrite
  if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
    ok "Skipped ReaPack update."
  else
    curl -L --progress-bar "$REAPACK_URL" -o "$REAPACK_DEST" || error "ReaPack download failed."
    ok "ReaPack updated."
  fi
else
  log "Downloading ReaPack..."
  curl -L --progress-bar "$REAPACK_URL" -o "$REAPACK_DEST" || error "ReaPack download failed."
  ok "ReaPack installed."
fi

log "Clearing quarantine flag on ReaPack..."
xattr -dr com.apple.quarantine "$REAPACK_DEST" 2>/dev/null || true

# ============================================================
#  DONE
# ============================================================
echo -e "\n${BOLD}============================================${NC}"
echo -e "${GREEN}${BOLD}   All done! Installed:${NC}"
echo -e "   SWS Extension  $SWS_VERSION"
echo -e "   ReaPack        (latest)"
echo -e "${BOLD}============================================${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "  1. Open REAPER"
echo -e "  2. If macOS blocks SWS: System Settings -> Privacy & Security -> Allow Anyway"
echo -e "  3. Extensions -> ReaPack -> Synchronize packages"
echo -e "  4. Enjoy!\n"