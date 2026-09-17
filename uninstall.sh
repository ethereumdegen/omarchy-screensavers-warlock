#!/bin/bash

# Remove the warlock screensaver pack.
#
#   ./uninstall.sh [--purge]
#
#   --purge  also delete the installed screensaver sets

set -euo pipefail

OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
BIN_DIR="$CONFIG_DIR/bin"
SETS_DIR="$CONFIG_DIR/screensaver-sets"
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/screensaver-set"
UWSM_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/uwsm/env.d/50-omarchy-bin.sh"
BASHRC="$HOME/.bashrc"
MARKER="omarchy-screensavers-warlock"

purge=false
[[ ${1:-} == --purge ]] && purge=true

echo "==> Removing commands"
rm -f "$BIN_DIR"/{omarchy-screensaver,screensaver-set,screensaver-dev,screensaver-lib.sh}
rmdir "$BIN_DIR" 2>/dev/null || true

echo "==> Removing PATH wiring"
rm -f "$UWSM_ENV_FILE"
if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
  python3 - "$BASHRC" "$MARKER" <<'PY'
import sys

path, marker = sys.argv[1:3]
with open(path, encoding="utf-8") as handle:
    lines = handle.read().splitlines()

# The block starts at the marker comment and ends at its "esac"; nothing above it
# belongs to us.
start = next(i for i, line in enumerate(lines) if marker in line)
end = next(i for i in range(start, len(lines)) if lines[i].strip() == "esac")
del lines[start:end + 1]
while start < len(lines) and not lines[start].strip():
    del lines[start]

with open(path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines) + "\n")
PY
  echo "    removed PATH block from $BASHRC"
fi

echo "==> Restoring the stock screensaver art"
install -Dm644 "$OMARCHY_PATH/logo.txt" "$CONFIG_DIR/branding/screensaver.txt"
rm -f "$STATE_FILE"

if [[ $purge == true ]]; then
  echo "==> Deleting sets in $SETS_DIR"
  rm -rf "$SETS_DIR"
fi

cat <<'EOF'

Done. The packaged /usr/bin/omarchy-screensaver takes over again (a new login
clears the PATH override from the running session; nothing else is needed).
Remove the "style.screensaver.sets" rows from
~/.config/omarchy/extensions/omarchy-menu.jsonc if you installed them.
EOF
