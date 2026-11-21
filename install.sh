#!/bin/zsh
# Build and install notchshelf.app into /Applications.
#
#   ./install.sh              build, install, launch
#   ./install.sh --uninstall  quit and remove (the shelf folder is left alone)
set -e
cd "$(dirname "$0")"

TARGET="/Applications/notchshelf.app"

quit_running() {
  osascript -e 'if application "notchshelf" is running then tell application "notchshelf" to quit' 2>/dev/null || true
  pkill -x notchshelf 2>/dev/null || true
  sleep 0.5
}

if [[ "$1" == "--uninstall" ]]; then
  quit_running
  rm -rf "$TARGET"
  echo "removed $TARGET"
  echo "shelf left alone: ~/Library/Application Support/notchshelf"
  exit 0
fi

./scripts/build.sh
quit_running

# Stage next to the target and swap in one step, so a failed copy never
# leaves a half-installed app.
STAGE="$TARGET.new"
rm -rf "$STAGE"
cp -R notchshelf.app "$STAGE"
rm -rf "$TARGET"
mv "$STAGE" "$TARGET"
open "$TARGET"
echo "installed → $TARGET"
