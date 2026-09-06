# B+Hybrid — Escape Hatch for Retained-Native Widgets

Half-elmish (`dispatch → pure updateModel → Cmd/Sub` + imperative `updateView` only) is optimal for `lib_core` business logic. GTK4 widgets that own retained-native state (`WebKit.WebView`, `Shumate.Map`, `GStreamer` pipeline, `Gtk.DrawingArea` with drag) break the `updateView` pure-render assumption: they keep `BackForwardList`, `WebContext`, `loaded_url` cache, tile cache, etc., that must be reset imperatively.

`B+hybrid` is **not** a second architecture — it is half-elmish plus a narrow imperative escape **per-view**, keeping the `dispatch→updateModel→Cmd` loop intact and `lib_core` GTK-free. Start half-elmish always (`docs/ARCHITECTURE.md`); adopt `B+hybrid` incrementally only for the view that needs it (`docs/MIGRATING_TO_HYBRID.md` checklist).

## Decision rule — when to adopt

All three must hold; otherwise stay half-elmish (`README.md` table):

1. Widget keeps retained-native state outside GTK property bindings.
2. Rebuilding it from `model` in `updateView` would recreate/lose state every message.
3. Events arrive at continuous rate (`value_changed`, `motion`, etc.) — coalescing needed.

Half-elmish examples: `Counter` `src/components/counter/` · notes-store `src/model/messages.vala`.
B+hybrid examples: `vCHM` `src/view/viewer.vala:15` `WebKit.WebView` `loaded_url:362` `register_uri_scheme:52` + `TreeView` `src/view/topics.vala:11` `syncing` storm.

## What adopting adds — only this (additive)

* One meson toggle `meson_options.txt:hybrid` (`half` default → `b_hybrid` when needed) + `meson.build` `hybrid_mode` `#if B_HYBRID` compile-time gate. With `hybrid=half`, hybrid files are ignored — existing app unchanged.
* One reference file `src/hybrid_example.vala` (`#if B_HYBRID` `HybridView` coalesced-scroll demo) — not required in production, copy the `value_changed` snippet per-view instead.
* This doc + `docs/MIGRATING_TO_HYBRID.md` (per-view `current_ctx` checklist).
* No changes to `src/elmish.vala` loop, `src/model/messages.vala` `kind`, `src/app-update.vala` pure, `lib_core` stays no-GTK.

## Pattern per-view (from vCHM `design.md:32`)

Minimal — add a per-view context, keep the loop:

```vala
// Model: one context per resource (e.g. per book)
private App.BookContext _empty_book = new App.BookContext ();
private App.BookContext? _active_ctx = null;
public App.BookContext current_ctx { get { return _active_ctx ?? _empty_book; } }
public void set_active (App.BookContext? ctx) {
    if (_active_ctx != null && _active_ctx != ctx) { /* flush/coalesce */ }
    _active_ctx = ctx;
    notify_property ("current_ctx");
}
```

```vala
// View: single widget instance, recreated only on current_ctx change + coalesced native events
view.notify["current_ctx"].connect (() => recreate_for_new_ctx ());
var vadj = scrolled.get_vadjustment ();
vadj.value_changed.connect (() => {
  pending_y = (int) vadj.get_value ();
  if (coalesce_id == 0) coalesce_id = Timeout.add (1500, () => { save; coalesce_id = 0; return false; });
});
```

Apply only to the view that owns the retained-native widget; other views stay plain half-elmish.

## How to enable

* **New project (post-clone, template):** `scripts/scaffold.sh --b-hybrid` sets `meson_options.txt:hybrid=b_hybrid`; branch `b+hybrid` is pre-enabled `hybrid=b_hybrid`.
* **Already-developed project (incremental, no re-clone):** `scripts/adopt-hybrid.sh --check` preview → `--apply` idempotent apply (`meson_options.txt` toggle + `meson.build` gate + `src/hybrid_example.vala` in executable sources, if missing). Then `meson setup builddir -Dhybrid=b_hybrid` and apply the per-view pattern above to the one view that needs it. See `docs/MIGRATING_TO_HYBRID.md`.

## Toolkit — what stays, what changes

* **Stays:** `src/elmish.vala` loop, `lib_core` no-GTK, headless `meson test` (`test_update`, `test_elmish`), `docs/ARCHITECTURE.md` flow.
* **Changes only when `B_HYBRID`:** the adopted view + its context (`notify["current_ctx"]`). View still receives `dispatch` → `updateModel` → `updateView`; `B_HYBRID` code is behind `--define=B_HYBRID`, so `hybrid=half` build ignores it.
