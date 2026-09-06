#!/usr/bin/env bash
# adopt-hybrid.sh — incrementally add B+hybrid toggle to an already-developed half-elmish project.
# Additive only: one meson_options toggle + one reference file + a meson.build gate.
# lib_core stays GTK-free. Idempotent.
# Usage:
#   ./scripts/adopt-hybrid.sh --check            # preview diff, no writes
#   ./scripts/adopt-hybrid.sh --apply            # idempotent apply
#   ./scripts/adopt-hybrid.sh --revert           # back to half-elmish (hybrid=half, keeps example)
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
      echo "  --apply  add B+hybrid toggle (meson_options.txt + src/hybrid_example.vala + meson.build gate)"
      echo "  --revert set meson_options hybrid=half (keeps example if present)"
      exit 0 ;;
    -*) echo "Unknown: $arg" >&2; exit 1 ;;
    *) echo "Too many args: $arg" >&2; exit 1 ;;
  esac
done
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
NEED_MESON_OPTS=false; NEED_EXAMPLE=false; NEED_MESON_BUILD_PATCH=false

# Check meson_options.txt — has an 'option('hybrid'' block? (may share the file with other options)
if [[ ! -f meson_options.txt ]]; then
  NEED_MESON_OPTS=true
elif ! grep -q "option('hybrid'" meson_options.txt 2>/dev/null; then
  NEED_MESON_OPTS=true
fi
# Check hybrid_example.vala
if [[ ! -f src/hybrid_example.vala ]]; then NEED_EXAMPLE=true; fi
# Check meson.build gating (add_project_arguments behind hybrid_mode) + example in sources
if [[ -f meson.build ]] && ! grep -q "get_option('hybrid')" meson.build; then NEED_MESON_BUILD_PATCH=true; fi
if [[ -f meson.build ]] && ! grep -q "hybrid_example" meson.build; then NEED_MESON_BUILD_PATCH=true; fi

if [[ "$MODE" == "check" ]]; then
  echo "→ adopt-hybrid --check (additive, no writes)"
  if [[ "$NEED_MESON_OPTS" == true ]]; then echo "  + would add 'option('hybrid')' to meson_options.txt (keeps existing options)"; else echo "  = meson_options.txt already has hybrid toggle"; fi
  if [[ "$NEED_MESON_BUILD_PATCH" == true ]]; then echo "  + would patch meson.build: hybrid_mode gate + add src/hybrid_example.vala to executable sources"; else echo "  = meson.build already gates B_HYBRID and compiles the example"; fi
  if [[ "$NEED_EXAMPLE" == true ]]; then echo "  + would create src/hybrid_example.vala (#if B_HYBRID coalesced-scroll demo)"; else echo "  = src/hybrid_example.vala already present"; fi
  echo "→ After --apply: meson setup builddir -Dhybrid=b_hybrid; per-view checklist: docs/MIGRATING_TO_HYBRID.md (template repo)"
  echo "→ No rewrites: lib_core stays GTK-free, half-elmish views unchanged"
  exit 0
fi

if [[ "$MODE" == "revert" ]]; then
  if [[ -f meson_options.txt ]]; then
    # Anchor to the hybrid block: only flip the value line following option('hybrid'
    python3 - <<'PY' || true
import pathlib
p = pathlib.Path("meson_options.txt")
lines = p.read_text().splitlines(keepends=True)
for i, ln in enumerate(lines):
    if ln.strip().startswith("option('hybrid'"):
        for j in range(i, min(i + 6, len(lines))):
            if "value:" in lines[j]:
                lines[j] = lines[j].replace("value: 'b_hybrid'", "value: 'half'")
                break
        break
p.write_text("".join(lines))
PY
    echo "→ reverted meson_options.txt to value: 'half' (example + meson.build gate kept; both inert in half mode)"
  fi
  echo "→ half-elmish active: meson setup builddir (hybrid=half ignores #if B_HYBRID)"
  exit 0
fi

# --apply
echo "→ adopt-hybrid --apply (idempotent)"

# 1. meson_options.txt — create or append (never overwrite existing options)
if [[ "$NEED_MESON_OPTS" == true ]]; then
  if [[ -f meson_options.txt ]]; then
    printf '\n' >> meson_options.txt
    cat >> meson_options.txt <<'EOF'
option('hybrid',
  type: 'combo',
  choices: ['half', 'b_hybrid'],
  value: 'b_hybrid',
  description: 'Architecture mode: half-elmish (pure) or B+hybrid (escape hatch for retained-native widgets like WebView/Map)')
EOF
    echo "  + appended 'option('hybrid')' to meson_options.txt (existing options kept)"
  else
    cat > meson_options.txt <<'EOF'
option('hybrid',
  type: 'combo',
  choices: ['half', 'b_hybrid'],
  value: 'b_hybrid',
  description: 'Architecture mode: half-elmish (pure) or B+hybrid (escape hatch for retained-native widgets like WebView/Map)')
EOF
    echo "  + created meson_options.txt (hybrid=b_hybrid)"
  fi
else
  # Anchor to the hybrid block so other options are never touched
  python3 - <<'PY' || true
import pathlib
p = pathlib.Path("meson_options.txt")
lines = p.read_text().splitlines(keepends=True)
for i, ln in enumerate(lines):
    if ln.strip().startswith("option('hybrid'"):
        for j in range(i, min(i + 6, len(lines))):
            if "value:" in lines[j]:
                lines[j] = lines[j].replace("value: 'half'", "value: 'b_hybrid'")
                break
        break
p.write_text("".join(lines))
PY
  echo "  = meson_options.txt set to b_hybrid"
fi

# 2. meson.build — gate + make sure the example is actually compiled
if [[ "$NEED_MESON_BUILD_PATCH" == true ]]; then
  python3 <<'PY'
import pathlib, re
p = pathlib.Path("meson.build")
t = p.read_text()
changed = []
# Insert hybrid gate after 'project(...)' block if missing
if "get_option('hybrid')" not in t:
    m = re.search(r"^project\(.*?^\)\s*$", t, flags=re.MULTILINE | re.DOTALL)
    if not m:
        raise SystemExit("ERROR: could not locate project() block in meson.build — patch manually")
    insert = ("\n\nhybrid_mode = get_option('hybrid')\n"
              "message('Hybrid mode: @0@'.format(hybrid_mode))\n"
              "\n"
              "if hybrid_mode == 'b_hybrid'\n"
              "  add_project_arguments(['--define=B_HYBRID'], language: 'vala')\n"
              "endif\n")
    t = t[:m.end()] + insert + t[m.end():]
    changed.append("gate")
# Add the example to the executable sources so it is actually compiled.
# Safe in 'half' mode: the file is entirely #if B_HYBRID, so it compiles to an
# empty translation unit (GTK-free) when the define is absent.
if "'src/hybrid_example.vala'" not in t:
    m = re.search(r"executable\(", t)
    if not m:
        raise SystemExit("ERROR: could not locate executable() in meson.build — add 'src/hybrid_example.vala' to its sources manually")
    am = re.search(r"\[\s*\n", t[m.end():])
    if not am:
        raise SystemExit("ERROR: could not locate executable() sources array in meson.build — add 'src/hybrid_example.vala' to its sources manually")
    pos = m.end() + am.end()
    t = t[:pos] + "    'src/hybrid_example.vala',\n" + t[pos:]
    changed.append("sources")
p.write_text(t)
print("patched meson.build: " + (", ".join(changed) if changed else "no changes"))
PY
  if grep -q "get_option('hybrid')" meson.build && grep -q "'src/hybrid_example.vala'" meson.build; then
    echo "  + patched meson.build: hybrid_mode gate + src/hybrid_example.vala in executable sources"
  else
    echo "  ! meson.build patch incomplete — add manually: hybrid_mode = get_option('hybrid') + add_project_arguments(['--define=B_HYBRID']) when b_hybrid, and src/hybrid_example.vala to executable sources"
  fi
else
  echo "  = meson.build already gates B_HYBRID and compiles the example"
fi

# 3. src/hybrid_example.vala reference file
if [[ "$NEED_EXAMPLE" == true ]]; then
  mkdir -p src
  cat > src/hybrid_example.vala <<'EOF'
// SPDX-License-Identifier: MIT
// B+hybrid example — retained-native widget escape hatch.
// Adopted incrementally via scripts/adopt-hybrid.sh; compiled only with
// -Dhybrid=b_hybrid (in half mode this file is an inert empty unit).
#if B_HYBRID
using Gtk;
using App;

// BookContext-like per-widget state with the current_ctx proxy pattern
// (see docs/B_HYBRID.md). The loop stays half-elmish; only the view that
// owns retained-native state uses this escape.
public class App.HybridModel {
    public int count = 0;
    // Per-resource state + proxy, e.g.:
    // private HybridCtx _empty = new HybridCtx ();
    // private HybridCtx? _active = null;
    // public HybridCtx current_ctx { get { return _active ?? _empty; } }
    // public void set_active (HybridCtx? ctx) {
    //     if (_active != null && _active != ctx) { /* flush pending coalesced state */ }
    //     _active = ctx;
    //     notify_property ("current_ctx");
    // }
}

// Coalesced scroll via GtkAdjustment.value_changed (not a Message per pixel).
// Timeout 1500ms coalesce, heavy save (GSettings/per-book rows) only on flush.
// This is why B+hybrid bypasses dispatch for continuous native events.
public class App.HybridView : Gtk.Box {
    private uint coalesce_id = 0;
    private int pending_y = 0;
    public HybridView() { Object(orientation: Gtk.Orientation.VERTICAL); }
    public void bind_coalesced_scroll(Gtk.ScrolledWindow scrolled) {
        var adj = scrolled.get_vadjustment();
        adj.value_changed.connect(() => {
            pending_y = (int) adj.get_value();  // capture latest position every event
            if (coalesce_id == 0) {
                coalesce_id = GLib.Timeout.add(1500, () => {
                    // flush pending_y to model/GSettings here
                    coalesce_id = 0;
                    return false;
                });
            }
        });
    }
}
#endif
EOF
  echo "  + created src/hybrid_example.vala"
else
  echo "  = src/hybrid_example.vala already present"
fi
echo "Done. Next: meson setup builddir -Dhybrid=b_hybrid && see docs/MIGRATING_TO_HYBRID.md (in the template repo)"
echo "Note: the example uses the App namespace — adapt to your namespace before adopting per-view (docs/B_HYBRID.md)."
echo "Rollback: $0 --revert  or  meson setup builddir -Dhybrid=half"