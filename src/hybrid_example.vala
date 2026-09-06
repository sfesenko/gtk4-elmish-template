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
