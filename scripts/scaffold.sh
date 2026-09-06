#!/usr/bin/env bash
set -euo pipefail
MODE="half"; APP_NAME=""; APP_ID=""
for arg in "$@"; do
  case "$arg" in
    --half) MODE="half" ;;
    --b-hybrid|--b_hybrid|--hybrid) MODE="b_hybrid" ;;
    --help|-h) echo "Usage: $0 [--half|--b-hybrid] [APP_NAME] [APP_ID]"; exit 0 ;;
    -*) echo "Unknown: $arg" >&2; exit 1 ;;
    *) if [[ -z "$APP_NAME" ]]; then APP_NAME="$arg"; elif [[ -z "$APP_ID" ]]; then APP_ID="$arg"; else echo "Too many args" >&2; exit 1; fi ;;
  esac
done
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
if [[ "$MODE" == "b_hybrid" ]]; then
  echo "→ B+hybrid (meson_options:hybrid=b_hybrid)"; sed -i "s/value: 'half'/value: 'b_hybrid'/" meson_options.txt
else
  echo "→ half-elmish (meson_options:hybrid=half)"; sed -i "s/value: 'b_hybrid'/value: 'half'/" meson_options.txt
fi
if [[ -n "$APP_NAME" ]]; then echo "→ $APP_NAME"; sed -i "s/project('half-elmish-template'/project('$APP_NAME'/" meson.build; fi
if [[ -n "$APP_ID" ]]; then echo "→ $APP_ID"; sed -i "s/com\.example\.half_elmish_template/$APP_ID/g" meson.build; sed -i "s/com\.example\.half_elmish_template/$APP_ID/g" src/main.vala; fi
echo "Done. meson setup builddir $([[ $MODE == b_hybrid ]] && echo -Dhybrid=b_hybrid)"; echo "See docs/B_HYBRID.md"
