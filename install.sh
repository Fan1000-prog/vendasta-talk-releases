#!/bin/bash
# VendastaTalk installer — sets up everything needed to run the app.
#
# Usage:
#   bash install.sh [--with-ai] [path/to/VendastaTalk_x.y.z_arch.dmg]
#
# If no DMG path is given, the script looks for one in ~/Downloads and
# next to the script itself. Safe to re-run: every step is skipped if
# already done.
#
# What it does:
#   1. Installs Homebrew (if missing)
#   2. Installs whisper-cpp via Homebrew
#   3. Downloads the Whisper speech model (~142 MB)
#   4. Installs VendastaTalk.app from the DMG and removes the quarantine
#      flag (the app is ad-hoc signed, not notarized)
#
# With --with-ai it also installs Ollama and pulls the AI cleanup model
# (~2 GB). Only needed if you switch Cleanup to "AI" in Settings — the
# default Fast cleanup works without it, and you can re-run this script
# with --with-ai later at any time.

set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/com.vendasta.vendastatalk"
WHISPER_MODEL_PATH="$APP_SUPPORT/models/ggml-base.en.bin"
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
OLLAMA_MODEL="llama3.2:3b"
OLLAMA_URL="http://localhost:11434"

step()  { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
ok()    { printf '\033[1;32m    ✓ %s\033[0m\n' "$1"; }
fail()  { printf '\033[1;31m    ✗ %s\033[0m\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "VendastaTalk is macOS-only."

WITH_AI=0
if [ "${1:-}" = "--with-ai" ]; then
  WITH_AI=1
  shift
fi

# ---------------------------------------------------------------- Homebrew
step "Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  # Standard locations, in case brew is installed but not on PATH yet
  for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$brew_path" ] && eval "$("$brew_path" shellenv)" && break
  done
fi
if command -v brew >/dev/null 2>&1; then
  ok "already installed"
else
  echo "    Installing Homebrew (you may be asked for your Mac password)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$brew_path" ] && eval "$("$brew_path" shellenv)" && break
  done
  command -v brew >/dev/null 2>&1 || fail "Homebrew install finished but 'brew' is not on PATH. Open a new terminal and re-run this script."
  ok "installed"
fi

# ------------------------------------------------------------- whisper-cpp
step "whisper-cpp (speech-to-text engine)"
if command -v whisper-cli >/dev/null 2>&1; then
  ok "already installed"
else
  brew install whisper-cpp
  ok "installed"
fi

# ------------------------------------------------------- Ollama (optional)
if [ "$WITH_AI" = "1" ]; then
  step "Ollama (local AI for transcript cleanup)"
  if [ -d "/Applications/Ollama.app" ] || command -v ollama >/dev/null 2>&1; then
    ok "already installed"
  else
    # Cask was renamed ollama -> ollama-app; try both for older brew indexes
    brew install --cask ollama-app 2>/dev/null || brew install --cask ollama
    ok "installed"
  fi

  step "Starting Ollama"
  if curl -sf "$OLLAMA_URL" >/dev/null 2>&1; then
    ok "already running"
  else
    if [ -d "/Applications/Ollama.app" ]; then
      open -a Ollama
    else
      (ollama serve >/dev/null 2>&1 &)
    fi
    for _ in $(seq 1 30); do
      curl -sf "$OLLAMA_URL" >/dev/null 2>&1 && break
      sleep 2
    done
    curl -sf "$OLLAMA_URL" >/dev/null 2>&1 || fail "Ollama did not start. Open the Ollama app manually, then re-run this script."
    ok "running"
  fi

  step "Cleanup model ($OLLAMA_MODEL, ~2 GB — one-time download)"
  if curl -sf "$OLLAMA_URL/api/tags" | grep -q "\"$OLLAMA_MODEL\""; then
    ok "already downloaded"
  else
    ollama pull "$OLLAMA_MODEL"
    ok "downloaded"
  fi
else
  step "Ollama (optional AI cleanup)"
  ok "skipped — the default Fast cleanup needs no AI model. Re-run with --with-ai to add it."
fi

# ----------------------------------------------------------- Whisper model
step "Whisper speech model (~142 MB — one-time download)"
if [ -s "$WHISPER_MODEL_PATH" ]; then
  ok "already downloaded"
else
  mkdir -p "$(dirname "$WHISPER_MODEL_PATH")"
  # -C - resumes a partial download if the script was interrupted
  curl -L -C - --progress-bar -o "$WHISPER_MODEL_PATH" "$WHISPER_MODEL_URL" \
    || fail "Whisper model download failed. Check your connection and re-run this script — it resumes where it left off."
  ok "downloaded"
fi

# --------------------------------------------------------------- App (DMG)
step "VendastaTalk.app"
RELEASES_REPO="Fan1000-prog/vendasta-talk-releases"

find_dmg() {
  # Newest VendastaTalk DMG from ~/Downloads or next to this script
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # `|| true`: no matches must not kill the script under set -e -o pipefail
  ls -t "$HOME/Downloads"/VendastaTalk*.dmg "$script_dir"/VendastaTalk*.dmg 2>/dev/null | head -1 || true
}

download_latest_dmg() {
  # Grab the newest DMG from the public releases repo. After this first
  # install the app updates itself, so this only runs once per machine.
  echo "    Downloading the latest release from GitHub..." >&2
  local url
  url="$(curl -sf "https://api.github.com/repos/$RELEASES_REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | cut -d'"' -f4 || true)"
  [ -n "$url" ] || return 1
  local dest="$HOME/Downloads/$(basename "$url")"
  curl -L --progress-bar -o "$dest" "$url" || return 1
  echo "$dest"
}

if [ -d "/Applications/VendastaTalk.app" ] && [ -z "${1:-}" ]; then
  DMG=""
  ok "already in /Applications (the app updates itself from Settings)"
else
  DMG="${1:-$(find_dmg)}"
  if [ -z "$DMG" ]; then
    DMG="$(download_latest_dmg)" \
      || fail "Could not download the latest release from github.com/$RELEASES_REPO. Check your connection, or download the DMG manually and re-run this script."
  fi
  [ -f "$DMG" ] || fail "DMG not found: $DMG"
fi
if [ -n "$DMG" ]; then
  echo "    Installing from: $DMG"
  MOUNT_POINT="$(mktemp -d /tmp/vendastatalk-dmg.XXXXXX)"
  hdiutil attach "$DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet \
    || fail "Could not mount $DMG"
  trap 'hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true' EXIT
  [ -d "$MOUNT_POINT/VendastaTalk.app" ] || fail "DMG does not contain VendastaTalk.app"
  rm -rf /Applications/VendastaTalk.app
  cp -R "$MOUNT_POINT/VendastaTalk.app" /Applications/
  hdiutil detach "$MOUNT_POINT" -quiet
  trap - EXIT
  ok "installed to /Applications"
fi

# App is ad-hoc signed (free internal tool, not Apple-notarized) — remove
# the quarantine flag so Gatekeeper doesn't block the first launch.
xattr -dr com.apple.quarantine /Applications/VendastaTalk.app 2>/dev/null || true

# ------------------------------------------------------------------- Done
step "All set — launching VendastaTalk"
open -a VendastaTalk
cat <<'EOF'

    Two permissions to grant on first run (the app's Setup checklist
    walks you through both):

      1. Microphone     — click Allow when macOS asks
      2. Accessibility  — System Settings > Privacy & Security >
                          Accessibility > enable VendastaTalk

    Then hold Cmd+Shift+Space and talk. Release to paste.
EOF
