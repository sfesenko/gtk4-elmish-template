#!/usr/bin/env bash
# adopt-hybrid.sh — incrementally add B+hybrid toggle to an already-developed half-elmish project.
# Additive only: one meson_options toggle + one reference file. lib_core stays GTK-free.
# Usage:
#   ./scripts/adopt-hybrid.sh --check            # preview diff, no writes
#   ./scripts/adopt-hybrid.sh --apply            # idempotent apply
#   ./scripts/adopt-hybrid.sh --revert           # back to half-elmish (hybrid=half, keep example optionally)
#   ./scripts/adopt-hybrid.sh --check --apply    # same as --apply (check shown)
set -euo pipefail
MODE="check"
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --apply) MODE="apply" ;;
    --revert) MODE="revert" ;;
    --help|-h)
      echo "Usage: $0 [--check|--apply|--revert]"
      echo "  --check  preview changes (no writes)"
      echo "  --apply  add B+hybrid toggle (meson_options.txt + src/hybrid_example.vala)"
      echo "  --revert set meson_options hybrid=half (keeps example if present)"
      exit 0 ;;
    -*) echo "Unknown: $arg" >&2; exit 1 ;;
    *) echo "Too many args: $arg" >&2; exit 1 ;;
  esac
done
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
NEED_MESON_OPTS=false; NEED_EXAMPLE=false; NEED_MESON_BUILD_PATCH=false

# Check meson_options.txt
if [[ ! -f meson_options.txt ]]; then
  NEED_MESON_OPTS=true
else
  if ! grep -q "option('hybrid'" meson_options.txt 2>/dev/null; then NEED_MESON_OPTS=true; fi
fi
# Check hybrid_example.vala
if [[ ! -f src/hybrid_example.vala ]]; then NEED_EXAMPLE=true; fi
# Check meson.build gating (add_project_arguments behind hybrid_mode)
if [[ -f meson.build ]] && ! grep -q "get_option('hybrid')" meson.build; then NEED_MESON_BUILD_PATCH=true; fi

if [[ "$MODE" == "check" ]]; then
  echo "→ adopt-hybrid --check (additive, no writes)"
  if [[ "$NEED_MESON_OPTS" == true ]]; then echo "  + would create meson_options.txt (hybrid: half→b_hybrid toggle)"; else echo "  = meson_options.txt already has hybrid toggle"; fi
  if [[ "$NEED_MESON_BUILD_PATCH" == true ]]; then echo "  + would patch meson.build to gate --define=B_HYBRID behind hybrid_mode"; else echo "  = meson.build already gates B_HYBRID"; fi
  if [[ "$NEED_EXAMPLE" == true ]]; then echo "  + would create src/hybrid_example.vala (#if B_HYBRID coalesced-scroll demo)"; else echo "  = src/hybrid_example.vala already present"; fi
  echo "→ After --apply: meson setup builddir -Dhybrid=b_hybrid; see docs/MIGRATING_TO_HYBRID.md per-view checklist"
  echo "→ No rewrites: lib_core stays GTK-free, half-elmish views unchanged"
  exit 0
fi

if [[ "$MODE" == "revert" ]]; then
  if [[ -f meson_options.txt ]]; then
    sed -i "s/value: 'b_hybrid'/value: 'half'/" meson_options.txt || true
    echo "→ reverted meson_options.txt to value: 'half' (example kept if present)"
  fi
  echo "→ half-elmish active: meson setup builddir (hybrid=half ignores #if B_HYBRID)"
  exit 0
fi

# --apply
echo "→ adopt-hybrid --apply (idempotent)"
if [[ "$NEED_MESON_OPTS" == true ]]; then
  cat > meson_options.txt <<'EOF'
option('hybrid',
  type: 'combo',
  choices: ['half', 'b_hybrid'],
  value: 'b_hybrid',
  description: 'Architecture mode: half-elmish (pure) or B+hybrid (escape hatch for retained-native widgets like WebView/Map)')
EOF
  echo "  + created meson_options.txt (hybrid=b_hybrid)"
else
  sed -i "s/value: 'half'/value: 'b_hybrid'/" meson_options.txt || true
  echo "  = meson_options.txt set to b_hybrid"
fi
if [[ "$NEED_MESON_BUILD_PATCH" == true ]]; then
  # Auto-patch meson.build: insert hybrid_mode gate after 'project(...)' block
  if grep -q "^project(" meson.build; then
    # Insert after first project() closing paren block
    python3 <<'PY'
import pathlib, re
p = pathlib.Path("meson.build")
t = p.read_text()
if "get_option('hybrid')" not in t:
    # Insert hybrid gate after 'project(...)' block
    m = re.search(r"^project\(.*?^\)\s*$", t, flags=re.MULTILINE|re.DOTALL)
    if m:
        insert = "\n\nhybrid_mode = get_option('hybrid')\nmessage('Hybrid mode: @0@'.format(hybrid_mode))\n\nif hybrid_mode == 'b_hybrid'\n  add_project_arguments(['--define=B_HYBRID'], language: 'vala')\nendif\n"
        t = t[:m.end()] + insert + t[m.end():]
        # Also patch executable sources to conditional app_sources if still listing hybrid_example directly
        t = t.replace(
            "  [\n    'src/main.vala',\n    'src/app-view.vala',\n    'src/hybrid_example.vala',\n    config_file,\n  ],",
            "app_sources = [\n  'src/main.vala',\n  'src/app-view.vala',\n  config_file,\n]\nif hybrid_mode == 'b_hybrid'\n  app_sources += 'src/hybrid_example.vala'\nendif\n\nexecutable(\n  meson.project_name(),\n  app_sources,"
        )
        p.write_text(t)
        print("patched meson.build hybrid gate")
    else:
        print("could not locate project() for patch")
else:
    print("hybrid gate already present")
PY
    if grep -q "get_option('hybrid')" meson.build; then
      echo "  + patched meson.build hybrid gate (hybrid_mode + conditional src)"
    else
      echo "  ! meson.build missing hybrid gate — add manually: hybrid_mode = get_option('hybrid') + add_project_arguments(['--define=B_HYBRID']) when b_hybrid"
    fi
  fi
fi
if [[ "$NEED_EXAMPLE" == true ]]; then
  mkdir -p src
  cat > src/hybrid_example.vala <<'EOF'
#if B_HYBRID
using Gtk;
using App;
public class App.HybridView : Gtk.Box {
    private uint coalesce_id = 0;
    public HybridView() { Object(orientation: Gtk.Orientation.VERTICAL); }
    public void bind_coalesced_scroll(Gtk.ScrolledWindow scrolled) {
        var adj = scrolled.get_vadjustment();
        adj.value_changed.connect(() => {
            if (coalesce_id == 0) coalesce_id = GLib.Timeout.add(1500, () => { coalesce_id = 0; return false; });
        });
    }
}
#endif
EOF
  echo "  + created src/hybrid_example.vala"
else
  echo "  = src/hybrid_example.vala already present"
fi
echo "Done. Next: meson setup builddir -Dhybrid=b_hybrid && see docs/MIGRATING_TO_HYBRID.md"
echo "Rollback: $0 --revert  or  meson setup builddir -Dhybrid=half"
