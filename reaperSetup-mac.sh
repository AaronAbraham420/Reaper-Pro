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

# ── Create UserPlugins folder if missing ─────────────────────
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
SWS_RELEASE=$(curl -fsSL "$SWS_API") || error "Could not reach GitHub API. Check your internet connection."

# Extract macOS .pkg download URL
SWS_URL=$(echo "$SWS_RELEASE" | grep -o '"browser_download_url": "[^"]*\.pkg"' | head -1 | cut -d'"' -f4)

if [ -z "$SWS_URL" ]; then
  error "Could not find a .pkg download URL for SWS. Check https://github.com/reaper-oss/sws/releases manually."
fi

SWS_VERSION=$(echo "$SWS_RELEASE" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
log "Found SWS $SWS_VERSION → $SWS_URL"

SWS_PKG="$TMPDIR_CUSTOM/sws.pkg"
log "Downloading SWS..."
curl -L --progress-bar "$SWS_URL" -o "$SWS_PKG" || error "SWS download failed."

log "Installing SWS (requires admin password)..."
sudo installer -pkg "$SWS_PKG" -target / || error "SWS installation failed."
ok "SWS $SWS_VERSION installed successfully!"

# ============================================================
#  2. REAPACK
# ============================================================
echo -e "\n${BOLD}── Installing ReaPack ────────────────────────${NC}"

REAPACK_URL="https://reapack.com/files/reaper_reapack.dylib"
REAPACK_DEST="$REAPER_PLUGINS/reaper_reapack.dylib"

if [ -f "$REAPACK_DEST" ]; then
  warn "ReaPack already exists at $REAPACK_DEST"
  read -rp "Overwrite with latest version? (y/N): " overwrite
  [[ "$overwrite" =~ ^[Yy]$ ]] || { ok "Skipped ReaPack update."; }
fi

log "Downloading ReaPack..."
curl -L --progress-bar "$REAPACK_URL" -o "$REAPACK_DEST" || error "ReaPack download failed."
ok "ReaPack installed to $REAPACK_DEST"

# ── Remove macOS quarantine flags ────────────────────────────
log "Removing quarantine attributes (if any)..."
xattr -dr com.apple.quarantine "$REAPACK_DEST" 2>/dev/null || true
ok "Quarantine cleared."

# ============================================================
#  DONE
# ============================================================
echo -e "\n${BOLD}============================================${NC}"
echo -e "${GREEN}${BOLD}   All done! Here's what was installed:${NC}"
echo -e "   ✔ SWS Extension  $SWS_VERSION"
echo -e "   ✔ ReaPack        (latest)"
echo -e "${BOLD}============================================${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "  1. Open REAPER"
echo -e "  2. Go to Extensions → ReaPack → Synchronize packages"
echo -e "  3. Enjoy!\n"