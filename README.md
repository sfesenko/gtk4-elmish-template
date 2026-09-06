# half-elmish-template

A GitHub template for **Vala + GTK4** apps built on the **half-elmish**
architecture: a full elmish-style message/update loop (model, messages,
commands, subscriptions) with an imperative GTK view — the only deviation
from full Elm.

Includes a minimal working demo (a counter — button → dispatch → update →
view), the elmish core with `Cmd`/`Sub`/`Cmd.map` composition, and everything
a new GNOME-style app needs: meson build, i18n, appdata/desktop files, icons,
headless tests, Flatpak manifest, and an Arch Linux PKGBUILD.

- **Architecture docs:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — read
  this before extending the template.
- **B+hybrid escape:** [docs/B_HYBRID.md](docs/B_HYBRID.md) — when retained-native widgets need direct `notify`/`value_changed` coalesce.
- **Agent conventions:** [AGENTS.md](AGENTS.md)

## Build

Requirements: `meson`, `ninja`, `vala`, `gtk4` (≥ 4.10), `gettext`.

```bash
meson setup builddir
meson compile -C builddir
meson test -C builddir        # headless — no display needed
./builddir/half-elmish-template
```

This template **always starts as half-elmish** (pure `dispatch → updateModel → Cmd` + imperative view). It is the simplest, most testable, and fully sufficient for most apps. Only consider `B+hybrid` when a retained-native widget forces it — see [When to use B+hybrid](#when-to-use-bhybrid).

Scaffold from `main` (post-clone):

```bash
git clone https://github.com/sfesenko/gtk4-elmish-template my-app && cd my-app
./scripts/scaffold.sh --half my-app com.example.my_app       # default — pure half-elmish
# If you already know you need WebView/Map/Canvas/retained state later:
./scripts/scaffold.sh --b-hybrid my-app com.example.my_app
```

Already-developed app needing `B+hybrid` later (incremental, no re-clone):

```bash
./scripts/adopt-hybrid.sh --check   # preview what would change
./scripts/adopt-hybrid.sh --apply   # add hybrid toggle + example + meson.build gate (idempotent)
meson setup builddir -Dhybrid=b_hybrid
```

Branches (alternative to `scaffold.sh` flag):

* `half-elmish` — pure half-elmish, no hybrid files (`c0d804b` minimal).
* `main` — dual-scaffold, half-elmish default (`hybrid=half` + `B+hybrid` files, switch via `meson -Dhybrid=b_hybrid` or `scripts/scaffold.sh --b-hybrid`).
* `b+hybrid` — `B+hybrid` pre-enabled (`hybrid=b_hybrid` default, same files as `main` — diff is 1 line `meson_options.txt` `value`).

## When to use B+hybrid

`B+hybrid` is **not** a second architecture — it is half-elmish plus a narrow imperative escape inside the view/model boundary (`docs/B_HYBRID.md`). Keep it hidden until a retained-native widget requires it.

| Stay half-elmish | Switch to B+hybrid |
|---|---|
| `Counter` `src/components/counter/` · notes store `src/model/messages.vala` · any state fully derived from `model` and renderable by `updateView(msg,model,view)` | `WebKit.WebView` `Shumate.Map` `GStreamer` `DrawingArea` + `GestureDrag` — widget owns `BackForwardList`/`WebContext`/`loaded_url`/tile cache not reconstructible from `model` |
| Headless `meson test` (`test_update`) covers behavior | `value_changed` floods at pixel rate — `updateView` per-message would thrash → need `adjustment.value_changed` coalesced `1500ms` (`src/hybrid_example.vala`) |

**Rule:** start `half-elmish`; adopt `B+hybrid` incrementally per-view when the trigger above hits. The adoption adds one meson toggle, one example file, and a `meson.build` gate (`--define=B_HYBRID` + example in sources); `lib_core` stays GTK-free. See `docs/MIGRATING_TO_HYBRID.md` (checklist) and `docs/B_HYBRID.md` (pattern).

## What the template demonstrates

| Pattern | Where |
|---|---|
| Plain-class messages + `kind` enum discriminator (ref-counted, type-safe, generic-arg-compatible) | `src/model/messages.vala` |
| Pure, testable `updateModel` | `src/app-update.vala` |
| GTK-free core library (headless tests) | `meson.build` (`lib_core`) |
| Async side effects via `Cmd`, dispatching results back | `src/elmish.vala`, `src/app-update.vala` |
| Component composition via `Cmd.map` (own message types per component) | `src/elmish.vala` |
| Coalesced view updates | `src/elmish.vala` |
| Thread-safe dispatch (worker → main loop marshalling) | `src/elmish.vala` |
| Subscriptions (`Sub`, event sources) | `src/elmish.vala` |
| Imperative GTK4 view (signals → messages, `update` reflects model) | `src/app-view.vala` |

## Tests

```bash
meson test -C builddir
```

- `test_update` — model behavior for every message kind (5 tests)
- `test_elmish` — the core itself: Cmd chains, dispatch-back, coalescing,
  subscriptions, thread marshalling, `Cmd.map`, plain-class messages (12 tests)

All run without GTK — the core library imports nothing from GTK.

## Naming: half-elmish?

The loop is full elmish (dispatch → pure update → Cmd), the view is the only
exception: imperative widget mutation instead of a pure render function —
exactly the split the F# ecosystem calls "half-elmish" (Elmish.Uno,
Elmish.XamarinForms' StaticView). Model, messages, and update never deviate
from full Elm. If you prefer stricter purity, only `updateView` needs to
change: render everything from `model` and drop the `msg` parameter.

## Renaming the template

The project is named `half-elmish-template` with app id
`com.example.half_elmish_template` and namespace `App` (core: `Elmish`).
To make it yours:

1. Pick a repo name, e.g. `my-app`, and an app id following the
   `com.github.<username>.<name>` convention (hyphens become underscores).
2. Update: `meson.build` (`project()`), `src/main.vala` (application id),
   `data/com.example.half_elmish_template.{desktop.in,appdata.xml.in}` (file
   names + content), the two SVGs under `data/icons/`, `po/meson.build`
   (gettext domain), the Flatpak manifest, and `scripts/PKGBUILD`
   (`pkgname`, `pkgdesc`).
3. Rename namespaces (`App` → yours) and the demo counter to your first
   feature — the whole point of a template.
4. Update `_("Elmish Counter")`-style strings and this README.

## Packaging

**Arch Linux** — builds a package from the live work tree (uncommitted changes
included):

```bash
./scripts/build-package.sh              # → scripts/dist/*.pkg.tar.zst
./scripts/build-package.sh -C           # clean build; safe — the checkout is never touched
./scripts/build-package.sh -i           # install after building
```

`makepkg -C` wipes only a throwaway copy in `$srcdir`; your source tree is
untouched (verified behavior). `pkgver` in `scripts/PKGBUILD` must be bumped
with releases.

**Flatpak** — `com.example.half_elmish_template.json` builds the local tree:

```bash
flatpak-builder --user --install build-flatpak com.example.half_elmish_template.json
```

## License

MIT — see [LICENSE](LICENSE). Template code is yours to relicense; MIT keeps
every migration path open (GPL, closed-source, ...).
