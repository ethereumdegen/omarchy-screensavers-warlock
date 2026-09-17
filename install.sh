#!/bin/bash

# Install the warlock screensaver pack into an Omarchy system.
#
#   ./install.sh [--force] [--with-menu]
#
#   --force      overwrite screensaver sets that already exist
#   --with-menu  add "Style > Screensaver > Set" rows to the Omarchy menu

set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
BIN_DIR="$CONFIG_DIR/bin"
SETS_DIR="$CONFIG_DIR/screensaver-sets"
MENU_FILE="$CONFIG_DIR/extensions/omarchy-menu.jsonc"
UWSM_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/uwsm/env.d/50-omarchy-bin.sh"
BASHRC="$HOME/.bashrc"
MARKER="omarchy-screensavers-warlock"

force=false
with_menu=false
for arg in "$@"; do
  case $arg in
  --force) force=true ;;
  --with-menu) with_menu=true ;;
  -h | --help)
    sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Unknown option: $arg" >&2
    exit 1
    ;;
  esac
done

[[ -d $OMARCHY_PATH ]] || {
  echo "Omarchy not found at $OMARCHY_PATH" >&2
  exit 1
}
command -v ttfx >/dev/null || {
  echo "ttfx is required (it ships with Omarchy's screensaver). Install it first." >&2
  exit 1
}

echo "==> Installing commands into $BIN_DIR"
mkdir -p "$BIN_DIR"
install -m755 "$REPO_DIR"/bin/omarchy-screensaver "$REPO_DIR"/bin/screensaver-set \
  "$REPO_DIR"/bin/screensaver-dev "$BIN_DIR/"
install -m644 "$REPO_DIR"/bin/screensaver-lib.sh "$BIN_DIR/"

echo "==> Installing sets into $SETS_DIR"
mkdir -p "$SETS_DIR"
for set_dir in "$REPO_DIR"/sets/*/; do
  name=$(basename "$set_dir")
  if [[ -d $SETS_DIR/$name && $force == false ]]; then
    echo "    skipping existing set: $name (use --force to overwrite)"
    continue
  fi
  rm -rf "$SETS_DIR/$name"
  mkdir -p "$SETS_DIR/$name"
  cp -r "$set_dir". "$SETS_DIR/$name/"
  echo "    installed set: $name"
done

# A set that restores the stock Omarchy look, so switching back is one command.
if [[ ! -d $SETS_DIR/omarchy ]]; then
  mkdir -p "$SETS_DIR/omarchy"
  install -m644 "$OMARCHY_PATH/logo.txt" "$SETS_DIR/omarchy/art.txt"
  cat >"$SETS_DIR/omarchy/effects" <<'EOF'
# Empty effect list = ttfx picks from its whole catalogue, exactly like stock Omarchy.
EOF
  : >"$SETS_DIR/omarchy/palettes"
  echo "    installed set: omarchy (stock logo, stock behaviour)"
fi

# The runner shadows /usr/bin/omarchy-screensaver, so $BIN_DIR has to come first on
# PATH for both the Hyprland session (terminals, menu) and login shells (idle service).
echo "==> Wiring $BIN_DIR onto PATH"
mkdir -p "$(dirname "$UWSM_ENV_FILE")"
cat >"$UWSM_ENV_FILE" <<'EOF'
# Installed by omarchy-screensavers-warlock.
# Put ~/.config/omarchy/bin ahead of the packaged omarchy commands so the local
# screensaver runner wins for anything the Hyprland session spawns.
# Sourced by uwsm's prepare-env.sh; changes need a session restart.
case ":$PATH:" in
*":$HOME/.config/omarchy/bin:"*) ;;
*) PATH="$HOME/.config/omarchy/bin${PATH:+:$PATH}" ;;
esac
export PATH
EOF

if ! grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
  # Insert above the "not interactive, return" guard so non-interactive `bash -lc`
  # shells (the Omarchy shell's idle service) also resolve the local runner.
  python3 - "$BASHRC" "$MARKER" <<'PY'
import sys

path, marker = sys.argv[1:3]
block = f"""
# {marker}: local omarchy command forks must beat the packaged ones, including in
# the non-interactive `bash -lc` shells the Omarchy shell's idle service uses.
case ":$PATH:" in
*":$HOME/.config/omarchy/bin:"*) ;;
*) export PATH="$HOME/.config/omarchy/bin${{PATH:+:$PATH}}" ;;
esac
"""

with open(path, encoding="utf-8") as handle:
    lines = handle.read().splitlines()

guard = next((i for i, line in enumerate(lines) if "$-" in line and "return" in line), len(lines))
# Keep the guard's own comment block attached to it.
while guard > 0 and lines[guard - 1].lstrip().startswith("#"):
    guard -= 1
lines[guard:guard] = block.strip("\n").splitlines() + [""]

with open(path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines) + "\n")
PY
  echo "    added PATH block to $BASHRC"
else
  echo "    $BASHRC already wired"
fi

# Apply to the running compositor too, so nothing needs a re-login.
if command -v hyprctl >/dev/null && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hyprctl eval "hl.env('PATH', '$BIN_DIR:' .. (os.getenv('PATH') or ''))" >/dev/null 2>&1 &&
    echo "    applied to the running Hyprland session"
fi

if [[ $with_menu == true ]]; then
  echo "==> Adding menu rows to $MENU_FILE"
  mkdir -p "$(dirname "$MENU_FILE")"
  [[ -f $MENU_FILE ]] || printf '{\n}\n' >"$MENU_FILE"
  if grep -q 'style.screensaver.sets' "$MENU_FILE"; then
    echo "    menu rows already present"
  else
    python3 - "$MENU_FILE" "$REPO_DIR/menu/screensaver-sets.jsonc" <<'PY'
import sys

menu_path, rows_path = sys.argv[1:3]
with open(menu_path, encoding="utf-8") as handle:
    text = handle.read()
with open(rows_path, encoding="utf-8") as handle:
    rows = handle.read().rstrip("\n")

close = text.rstrip().rfind("}")
if close < 0:
    raise SystemExit(f"{menu_path} has no closing brace")
merged = text[:close].rstrip("\n") + "\n\n" + rows + "\n}\n"
with open(menu_path, "w", encoding="utf-8") as handle:
    handle.write(merged)
PY
    echo "    menu rows added (the menu hot-reloads)"
  fi
fi

echo "==> Activating the warlock set"
"$BIN_DIR/screensaver-set" set warlock

cat <<EOF

Done. Try it now:
  screensaver-set preview          # start the screensaver immediately
  screensaver-set list             # installed sets
  screensaver-set show             # art, effects, gradients, sample ttfx argv
  screensaver-set set omarchy      # back to the stock look

The idle screensaver (Omarchy shell, default 150s) now uses the active set.
EOF
