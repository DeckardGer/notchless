#!/bin/sh
# Notchless, container edition.
#
# The native app needs AppKit, NSScreen, a menu bar and a physical notch.
# This container has a terminal, so a terminal is what it gets.
set -eu

STYLE=fall
STRENGTH=0.5
DRAMATIC=1
TOTAL=0

usage() {
  cat <<'EOF'
Usage: notchless [--style retract|genie|fall]
                 [--strength gentle|firm|aggressive|nuclear]
                 [--no-dramatic] [--help]

Removes a notch this machine does not have. Works on anyone's machine.
EOF
}

die() {
  printf '%s\n' "$1" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --style)
      [ $# -ge 2 ] || die "--style needs a value"
      STYLE=$2
      shift 2
      ;;
    --strength)
      [ $# -ge 2 ] || die "--strength needs a value"
      case "$2" in
        gentle) STRENGTH=0.1; LABEL="Gentle" ;;
        firm) STRENGTH=0.5; LABEL="Firm" ;;
        aggressive) STRENGTH=0.8; LABEL="Aggressive" ;;
        nuclear) STRENGTH=1.0; LABEL="Nuclear ☢️" ;;
        *) die "Unknown strength: $2 (try Gentle, Firm, Aggressive or Nuclear)" ;;
      esac
      shift 2
      ;;
    --no-dramatic) DRAMATIC=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

case "$STYLE" in
  retract) STYLE_LABEL="Retract" ;;
  genie) STYLE_LABEL="Genie" ;;
  fall) STYLE_LABEL="Fall Off" ;;
  *) die "Unknown style: $STYLE (try retract, genie or fall)" ;;
esac

: "${LABEL:=Firm}"
SPEED=$(awk -v s="$STRENGTH" 'BEGIN { printf "%.2f", 0.7 + s * 0.9 }')
ANIMATE=0
if [ -t 1 ]; then
  ANIMATE=1
fi
PRINTED=0

pause() {
  t=$(awk -v t="$1" -v sp="$SPEED" 'BEGIN { printf "%.2f", t / sp }')
  TOTAL=$(awk -v a="$TOTAL" -v b="$t" 'BEGIN { printf "%.2f", a + b }')
  if [ "$ANIMATE" = 1 ]; then
    sleep "$t"
  fi
}

# Renders one three-line frame. On a TTY it redraws in place like an animation;
# otherwise it prints every frame, so CI logs get the whole movie unrolled.
frame() {
  if [ "$ANIMATE" = 1 ] && [ "$PRINTED" = 1 ]; then
    printf '\033[3A\r\033[J'
  fi
  printf '%s\n%s\n%s\n' "$1" "$2" "$3"
  PRINTED=1
  pause 0.25
}

edge='▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔'
edge2='▔▔▔▔▔▔▔▔▔▔████████████▔▔▔▔▔▔▔▔▔'
notch='         ████████████          '

printf '$ swiftc -O -swift-version 5 -target arm64-apple-macos14 Sources/main.swift\n'
if command -v swiftc >/dev/null 2>&1 && [ -f Sources/main.swift ]; then
  err=$(swiftc -typecheck Sources/main.swift 2>&1 | grep -m 1 'error:' || true)
  if [ -z "$err" ]; then
    err="Sources/main.swift: error: compiled, which is somehow worse"
  fi
  printf '%s\n' "$err"
else
  printf "Sources/main.swift:1:8: error: no such module 'AppKit'\n"
fi
printf "note: containers have no AppKit, no NSScreen and no notch.\n"
printf 'note: re-enacting the removal in this terminal instead.\n\n'

if [ "$DRAMATIC" = 1 ]; then
  printf 'Scanning display…\n'
  pause 0.8
  printf '0 displays found\n'
  pause 0.6
  printf 'No notch. Notchless draws one for you, then removes it.\n'
  printf '1 notch found\n'
fi

printf 'Removing notch…\n'
case "$STYLE" in
  retract)
    frame "$edge" "$notch" ""
    frame "$edge2" "" ""
    frame "$edge" "" ""
    ;;
  genie)
    frame "$edge" "$notch" ""
    frame "$edge" '        ████████████████       ' "$notch"
    frame "$edge" "" '           ████████            '
    frame "$edge" "" ""
    ;;
  fall)
    frame "$edge" "$notch" ""
    frame "$edge" '          ████████████         ' ""
    frame "$edge" "" '                  ████████████ '
    frame "$edge" "" ""
    ;;
esac

printf '\nNo notch detected\n'
printf 'Revealed the menu bar items hiding behind the notch (they are made up): ☁ 🛡 ☕ ♫ ✨\n'
printf 'Removed in %ss (%s, %s)\n' "$TOTAL" "$STYLE_LABEL" "$LABEL"
printf '\nDone. This machine is exactly as notchless as it was before. So is yours.\n'
