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
public class App.HybridModel : GLib.Object {
    public int count = 0;
    // Per-resource state + proxy, e.g. (GLib.Object base is required for notify_property):
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
// See vCHM src/app-view.vala:340 viewer_scrolled.get_vadjustment().value_changed:
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
