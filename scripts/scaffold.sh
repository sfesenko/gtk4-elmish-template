#!/usr/bin/env bash
# scaffold.sh — post-clone flag for half-elmish vs B+hybrid
# Usage: ./scripts/scaffold.sh [--half|--b-hybrid] [APP_NAME] [APP_ID]
#   APP_NAME: e.g. my-app (default: keep half-elmish-template)
#   APP_ID:   e.g. com.example.my_app (default: keep com.example.half_elmish_template)
set -euo pipefail

MODE="half"
APP_NAME=""
APP_ID=""

for arg in "$@"; do
  case "$arg" in
    --half) MODE="half" ;;
    --b-hybrid|--b_hybrid|--hybrid) MODE="b_hybrid" ;;
    --help|-h)
      echo "Usage: $0 [--half|--b-hybrid] [APP_NAME] [APP_ID]"
      echo "  --half       Pure half-elmish (default)"
      echo "  --b-hybrid   B+hybrid escape for retained-native widgets (WebView/Map)"
      echo "  APP_NAME     New project name (e.g. my-app)"
      echo "  APP_ID       New app id (e.g. com.example.my_app)"
      exit 0
      ;;
    -*) echo "Unknown option: $arg" >&2; exit 1 ;;
    *)
      if [[ -z "$APP_NAME" ]]; then APP_NAME="$arg"
      elif [[ -z "$APP_ID" ]]; then APP_ID="$arg"
      else echo "Too many positional args" >&2; exit 1; fi
      ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Meson option — set default in meson_options.txt so `meson setup` without -D picks the chosen mode
if [[ "$MODE" == "b_hybrid" ]]; then
  echo "→ Hybrid mode: B+hybrid (meson_options.txt:hybrid=b_hybrid)"
  sed -i "s/value: 'half'/value: 'b_hybrid'/" meson_options.txt
else
  echo "→ Hybrid mode: half-elmish (meson_options.txt:hybrid=half, default)"
  sed -i "s/value: 'b_hybrid'/value: 'half'/" meson_options.txt
fi

# Optional rename (APP_NAME/APP_ID) — done in python so names are not interpolated into sed
if [[ -n "$APP_NAME" || -n "$APP_ID" ]]; then
  APP_NAME="${APP_NAME:-half-elmish-template}"
  APP_ID="${APP_ID:-com.example.half_elmish_template}"
  echo "→ Renaming to $APP_NAME / $APP_ID"
  python3 - "$APP_NAME" "$APP_ID" <<'PY'
import pathlib, sys
name, appid = sys.argv[1], sys.argv[2]
old_name = "half-elmish-template"
old_id = "com.example.half_elmish_template"

def repl(path, pairs, rename=False):
    p = pathlib.Path(path)
    if not p.exists():
        return
    t = p.read_text()
    for a, b in pairs:
        t = t.replace(a, b)
    p.write_text(t)
    if rename:
        p.rename(str(p).replace(old_id, appid).replace(old_name, name))

# Content renames
repl("meson.build", [(old_name, name), (old_id, appid)])
repl("po/meson.build", [(old_name, name)])
repl("src/Config.vala.in", [(old_name, name)])
repl("src/main.vala", [(old_id, appid)])
repl("src/app-view.vala", [(old_id, appid)])
repl("data/meson.build", [(old_id, appid)])
repl("data/icons/meson.build", [(old_id, appid)])
repl("data/com.example.half_elmish_template.desktop.in", [(old_id, appid), (old_name, name)])
repl("data/com.example.half_elmish_template.appdata.xml.in", [(old_id, appid)])
repl("com.example.half_elmish_template.json", [(old_name, name), (old_id, appid)])
repl("po/POTFILES", [(old_id, appid)])
# Filename renames (data files, icons, flatpak manifest follow the app id / project name)
repl("data/com.example.half_elmish_template.desktop.in", [], rename=True)
repl("data/com.example.half_elmish_template.appdata.xml.in", [], rename=True)
repl("data/icons/hicolor/scalable/apps/com.example.half_elmish_template.svg", [], rename=True)
repl("data/icons/hicolor/symbolic/apps/com.example.half_elmish_template-symbolic.svg", [], rename=True)
repl("com.example.half_elmish_template.json", [], rename=True)
# lib_core stays a lib name; keep it aligned with the project name
repl("meson.build", [("half-elmish-core", name + "-core")])
PY
fi

echo "Done. Next:"
if [[ "$MODE" == "b_hybrid" ]]; then
  echo "  meson setup builddir -Dhybrid=b_hybrid"
  echo "  meson compile -C builddir && meson test -C builddir"
  echo "  See docs/B_HYBRID.md for when to use the escape hatch."
else
  echo "  meson setup builddir   # half-elmish (default)"
  echo "  meson compile -C builddir && meson test -C builddir"
fi