# Adopting B+Hybrid in an Already-Developed Project

This guide is for **existing half-elmish apps** that need a retained-native widget later (e.g. you started as `Notes`/`Counter` and now add `WebKit.WebView`, `Shumate.Map`, `GStreamer`, `DrawingArea`+drag). **Do not re-clone or re-scaffold.** Adoption is **additive** — one meson toggle + one reference file + a `meson.build` gate, `lib_core` stays GTK-free, other views unchanged.

## What adoption changes

```
half-elmish (before)  ──►  B+hybrid (after, per-view)
dispatch→updateModel→Cmd   dispatch→updateModel→Cmd  (unchanged)
updateView(msg,model,view) updateView(msg,model,view) + per-view escape
                       +─►  meson_options.txt:hybrid=b_hybrid
                       +─►  src/hybrid_example.vala (#if B_HYBRID demo)
                       ───  lib_core still no GTK, half-elmish views still pure
```

Files added: `meson_options.txt` (toggle), `src/hybrid_example.vala` (reference, `#if B_HYBRID`), `docs/B_HYBRID.md` (rule). `meson.build` gains the `hybrid_mode` gate (`--define=B_HYBRID`) plus the example in executable sources. No change to `src/elmish.vala`, `src/model/messages.vala` `kind`, `src/app-update.vala` purity.

## Checklist — apply incrementally per-view

Assume existing project has `src/model/messages.vala`, `src/app-update.vala`, `src/app-view.vala`, `tests/test_update.vala` (headless).

### 1. Enable the toggle (automated)

```bash
./scripts/adopt-hybrid.sh --check   # preview — no writes
./scripts/adopt-hybrid.sh --apply   # idempotent: adds meson_options.txt toggle + meson.build gate + src/hybrid_example.vala if missing
meson setup builddir -Dhybrid=b_hybrid
meson test -C builddir              # must stay green — hybrid ignored when half
```

Or manually: create `meson_options.txt` with `option('hybrid', combo ['half','b_hybrid'], value:'b_hybrid')` and make `meson.build` gate `add_project_arguments('--define=B_HYBRID')` when `b_hybrid` (already present in `main`).

### 2. Model — add per-view context (only for the retained-native view)

Do **not** replace `AppModel`; add a `BookContext`-like object per resource:

```vala
// src/model/my-context.vala (new, plain class, no GTK)
public class App.MyContext : GLib.Object {
    public string id { get; set; default = ""; }
    public string last_url { get; set; default = ""; }
    public double scroll_y { get; set; default = 0; }
    // retained per-resource state only
}
```

In `AppModel` (minimal diff — same as vCHM `design.md:32`):

```vala
private App.MyContext _empty = new App.MyContext ();
private App.MyContext? _active = null;
public App.MyContext current_ctx { get { return _active ?? _empty; } }
public void set_active (App.MyContext? ctx) {
    if (_active != null && _active != ctx) { /* flush pending coalesced */ }
    _active = ctx;
    notify_property ("current_ctx");
}
```

Add `current_ctx` to `updateModel` handled messages only for the view that needs it (e.g. `OPEN_FILE_DONE → set_active`, `NAVIGATE_DONE` uses `current_ctx`). Other messages unchanged.

### 3. View — apply escape only to the retained-native widget

* Keep one widget instance (e.g. one `WebView` / `Map`), recreate only on `notify["current_ctx"]` (vCHM `src/view/viewer.vala:122` pattern). Do not create per-message.
* Coalesce continuous events via `ScrolledWindow.get_vadjustment().value_changed` → `Timeout 1500ms` (see `src/hybrid_example.vala:33`). This is the `B+hybrid` part — it lives in the view, behind `#if B_HYBRID` if you want `hybrid=half` to skip it.

```vala
#if B_HYBRID
var vadj = scrolled.get_vadjustment ();
vadj.value_changed.connect (() => {
    pending_y = (int) vadj.get_value ();
    if (coalesce_id == 0) coalesce_id = Timeout.add (1500, () => { save; coalesce_id = 0; return false; });
});
#endif
```

Other views (`src/components/counter/` etc.) stay plain half-elmish — `updateView` per-message, no coalescing.

### 4. Keep `lib_core` GTK-free

`meson.build` `lib_core` must not list `src/hybrid_example.vala` or the new context if it imports GTK. Keep the context plain-GObject or put the `BookContext`-like class in `src/model/` with only `gio`. The view file (`src/app-view.vala`) already imports GTK; add the hybrid code there.

### 5. Tests — headless stay headless

Add model tests dispatching the new message and asserting `model.current_ctx` changes (like `tests/test_update.vala`). No GTK needed. View coalescing is manual QA — note this template's `meson.build` excludes `src/hybrid_example.vala` from sources in `hybrid=half` mode (adopt-patched trees compile it as an inert empty `#if B_HYBRID` unit instead), so run tests with `-Dhybrid=b_hybrid` to compile and exercise the demo.

## When this checklist is unnecessary

If the new widget has no retained-native state (`Gtk.Label`, `ListBox`, `ColumnView` with `ListStore`) or only one-shot loads (`FileDialog`, `AlertDialog`), stay half-elmish — drive it from a `Cmd` (`updateModel` returns `Cmd` that calls `view.load_uri` via `dispatch`). `B+hybrid` only when the trigger rule (`docs/ARCHITECTURE.md` three conditions) holds.

## Rollback

Prefer `scripts/adopt-hybrid.sh --revert`: it flips `meson_options.txt` back to `hybrid=half`, and the example file remains as an inert empty `#if B_HYBRID` unit. Full removal also requires deleting its sources line in `meson.build` — `rm src/hybrid_example.vala` alone breaks configuration because the file is listed in executable sources. `lib_core` tests still pass either way.
