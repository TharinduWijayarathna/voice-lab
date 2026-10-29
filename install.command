#!/bin/bash
# VoiceLab installer. Double-click this file in Finder (or run it in Terminal).
# It builds the app (Swift, needs macOS 26 and Xcode 26), sets up a private Python for the voice engine,
# downloads the voice model once (about 355 MB), and puts "VoiceLab" in your Applications folder.
# Run it again any time to update the app after changing its code here.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
SUPPORT="$HOME/Library/Application Support/VoiceLab"
VENV="$SUPPORT/venv"
MODELS="$SUPPORT/models"
APP="$HOME/Applications/VoiceLab.app"
MODEL_URL="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"

bold() { printf '\n\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$1"; echo "Press Return to close."; read -r _; exit 1; }
trap 'fail "Setup stopped because a step failed (see the message above)."' ERR

bold "Setting up VoiceLab"

# 0. macOS 26 and Swift (from Xcode 26)
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MAJOR" -lt 26 ]; then
  fail "VoiceLab needs macOS 26 (Tahoe) or later for its Liquid Glass window. This Mac has macOS $(sw_vers -productVersion)."
fi
if ! xcrun --find swift >/dev/null 2>&1; then
  fail "VoiceLab is built with Swift. Install Xcode 26 from the App Store, open it once, then run this again."
fi
echo "Using $(xcrun swift --version 2>/dev/null | head -1)"

mkdir -p "$SUPPORT" "$MODELS" "$HOME/Applications"

# 1. A Python the voice model supports (3.10 to 3.13)
ok_python() { "$1" -c 'import sys; sys.exit(0 if (3,10) <= sys.version_info[:2] < (3,14) else 1)' 2>/dev/null; }
PY=""
for c in python3.12 python3.13 python3.11 python3.10 \
         /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.11 \
         /usr/local/bin/python3.12 /usr/local/bin/python3.13 /usr/local/bin/python3.11 \
         /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 \
         /Library/Frameworks/Python.framework/Versions/3.13/bin/python3 \
         /Library/Frameworks/Python.framework/Versions/3.11/bin/python3 python3; do
  if command -v "$c" >/dev/null 2>&1 && ok_python "$(command -v "$c")"; then PY="$(command -v "$c")"; break; fi
done
if [ -z "$PY" ]; then
  UV="$(command -v uv || true)"
  if [ -z "$UV" ] && [ -x "$HOME/.local/bin/uv" ]; then UV="$HOME/.local/bin/uv"; fi
  if [ -z "$UV" ]; then
    echo "VoiceLab's voice engine needs Python 3.10 to 3.13, and this Mac doesn't have one."
    printf "Install a private copy now with uv (from astral.sh, about 40 MB)? [Y/n] "
    read -r yn
    case "$yn" in [nN]*) fail "Install Python 3.12 (brew install python@3.12, or python.org), then run this again." ;; esac
    curl -LsSf https://astral.sh/uv/install.sh | sh
    UV="$HOME/.local/bin/uv"
  fi
  "$UV" python install 3.12
  PY="$("$UV" python find 3.12)"
fi
echo "Using Python: $PY ($("$PY" --version))"

# 2. Its own environment, with the voice model's packages
if [ ! -x "$VENV/bin/python" ] || ! ok_python "$VENV/bin/python"; then
  rm -rf "$VENV"
  "$PY" -m venv "$VENV"
fi
bold "Installing the voice engine's packages (about 150 MB, the first time)"
"$VENV/bin/python" -m pip install --quiet --upgrade pip
"$VENV/bin/python" -m pip install --quiet -r "$SRC/engine/requirements.txt"

# 3. The voice model, once
get() {  # file, minimum size in bytes
  local f="$MODELS/$1"
  if [ -f "$f" ] && [ "$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f")" -ge "$2" ]; then echo "Already have $1"; return; fi
  echo "Downloading $1"
  curl -L --fail --progress-bar -o "$f.part" "$MODEL_URL/$1"
  mv "$f.part" "$f"
}
bold "Getting the voice model"
get kokoro-v1.0.onnx 300000000
get voices-v1.0.bin 25000000

# 4. The app: build the Swift window, then put it together with the engine and the icon
bold "Building VoiceLab (Swift)"
xcrun swift build -c release --package-path "$SRC/mac"
BIN="$(xcrun swift build -c release --package-path "$SRC/mac" --show-bin-path)/VoiceLab"

bold "Putting VoiceLab in your Applications folder"
rm -rf "$SUPPORT/app"   # the old web version kept a copy of its code here
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/engine"
cp "$BIN" "$APP/Contents/MacOS/VoiceLab"
cp "$SRC/icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$SRC/engine/engine.py" "$SRC/engine/server.py" "$APP/Contents/Resources/engine/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>VoiceLab</string>
  <key>CFBundleDisplayName</key><string>VoiceLab</string>
  <key>CFBundleIdentifier</key><string>com.eequate.voicelab</string>
  <key>CFBundleVersion</key><string>2.0</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>VoiceLab</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "(Couldn't sign the app for this Mac; it should still open.)"
touch "$APP"

trap - ERR
bold "Done. VoiceLab is in your Applications folder."
echo "Opening it now. To keep it handy, right-click its Dock icon and choose Options > Keep in Dock."
open "$APP"
