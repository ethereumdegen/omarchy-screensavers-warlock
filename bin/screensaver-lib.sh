#!/bin/bash
# shellcheck shell=bash

# Shared resolution logic for screensaver sets, sourced by omarchy-screensaver
# (the runner), screensaver-set (the switcher) and screensaver-dev (authoring).
#
# A set is ~/.config/omarchy/screensaver-sets/<name>/ containing:
#   art.txt or art/*.txt  art drawn by the screensaver; a directory rotates at random
#   effects               one "<ttfx-effect> [ttfx args...]" per line, blank = all effects
#   palettes              one "<name>: <color>..." per line, fed to --final-gradient-stops

SS_SETS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/screensaver-sets"
SS_STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/screensaver-set"
SS_BRANDING_ART="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/branding/screensaver.txt"

ss_active_set() {
  local name
  name=$(cat "$SS_STATE_FILE" 2>/dev/null) || return 0
  [[ -n $name && -d $SS_SETS_DIR/$name ]] && printf '%s\n' "$name"
}

ss_arts() {
  local name=$1
  if [[ -d $SS_SETS_DIR/$name/art ]]; then
    find "$SS_SETS_DIR/$name/art" -maxdepth 1 -name '*.txt' | sort
  elif [[ -f $SS_SETS_DIR/$name/art.txt ]]; then
    printf '%s\n' "$SS_SETS_DIR/$name/art.txt"
  fi
}

ss_random_art() {
  local art
  art=$(ss_arts "$1" | shuf -n1)
  printf '%s\n' "${art:-$SS_BRANDING_ART}"
}

# Uncommented, non-blank lines: "<effect> [args...]".
ss_effect_lines() {
  sed 's/#.*//' "$SS_SETS_DIR/$1/effects" 2>/dev/null | sed '/^[[:space:]]*$/d'
}

ss_effect_names() {
  ss_effect_lines "$1" | awk '{ print $1 }'
}

ss_palette_lines() {
  sed 's/#.*//' "$SS_SETS_DIR/$1/palettes" 2>/dev/null | sed '/^[[:space:]]*$/d'
}

ss_palette_names() {
  ss_palette_lines "$1" | awk -F: '{ gsub(/[[:space:]]/, "", $1); print $1 }'
}

# Colors of one palette, or of a random palette when the name is empty/"random".
ss_palette_colors() {
  local name=$1 wanted=${2:-random} line
  if [[ -z $wanted || $wanted == random ]]; then
    line=$(ss_palette_lines "$name" | shuf -n1)
  else
    line=$(ss_palette_lines "$name" | awk -F: -v w="$wanted" '{ key = $1; gsub(/[[:space:]]/, "", key); if (key == w) { sub(/^[^:]*:/, ""); print; exit } }')
    [[ -n $line ]] || return 1
  fi
  printf '%s\n' "${line#*:}"
}

# Build the full ttfx argv for one pass into the SS_ARGV array.
# Usage: ss_build_argv <set> [--art <file>] [--effect-line <line>] [--palette <name>]
ss_build_argv() {
  local name=$1 art="" effect_line="" palette=""
  shift
  while (($#)); do
    case $1 in
    --art)
      art=$2
      shift 2
      ;;
    --effect-line)
      effect_line=$2
      shift 2
      ;;
    --palette)
      palette=$2
      shift 2
      ;;
    *) return 2 ;;
    esac
  done

  [[ -n $art ]] || art=$(ss_random_art "$name")
  [[ -n $effect_line ]] || effect_line=$(ss_effect_lines "$name" | shuf -n1)

  SS_ARGV=(-i "$art"
    --frame-rate 120 --canvas-width 0 --canvas-height 0 --reuse-canvas
    --anchor-canvas c --anchor-text c --no-eol --no-restore-cursor)

  if [[ -z $effect_line ]]; then
    # No effect list: stock behaviour, ttfx picks from its whole catalogue. Per-effect
    # options (gradients, speeds) cannot be passed in this mode.
    SS_ARGV+=(--random-effect)
    return 0
  fi

  local -a effect_argv=()
  read -r -a effect_argv <<<"$effect_line"
  SS_ARGV+=("${effect_argv[@]}")

  local colors
  colors=$(ss_palette_colors "$name" "${palette:-random}") || colors=""
  if [[ -n ${colors// /} && $effect_line != *--final-gradient-stops* ]]; then
    local -a stops=()
    read -r -a stops <<<"$colors"
    SS_ARGV+=(--final-gradient-stops "${stops[@]}")
  fi
}
