# dolphin

Dolphin's settings, taken verbatim from [iNiR](https://github.com/snowarch/iNiR)
(`dots/.config/dolphinrc` and `dots/.config/kservicemenurc` there).

Both are **copied, not symlinked** by `install/bootstrap.sh` — Dolphin rewrites
`dolphinrc` itself on every window resize, view change and sort order, so a
symlink into this repo would turn ordinary use into a stream of local edits to
tracked files. Same reasoning as `dots/noctalia/settings.toml` and
`dots/happ/*.json`. `cp -n`: a re-run never overwrites settings changed since.

## dolphinrc

The parts that are preferences rather than state:

| setting | effect |
|---|---|
| `SingleClick=true` | one click opens a file — not Dolphin's default |
| `MenuBar=Disabled` | no menu bar; `Ctrl+M` brings it back |
| `ShowFullPath=true` | full path in the title bar instead of the folder name |
| `ShowStatusBar=FullWidth` | status bar spans the window |
| `ToolButtonStyle=IconOnly` | toolbar icons without labels |
| `GlobalViewProps=false` | view mode is remembered per folder |

`[PreviewSettings] Plugins` lists ~30 thumbnailers. Most belong to packages that
are not installed here (`ffmpegthumbs`, `kdegraphics-thumbnailers`, …) — Dolphin
ignores the ones it cannot find, so the list is harmless as it stands. Install
those two packages if you want video and document thumbnails.

## kservicemenurc

Which entries the right-click menu offers. Also inherited from iNiR, and it too
names things that are not installed (`filelight`, `kdeconnect`, `kio-admin`);
absent ones simply do not appear.

## What was deliberately left behind

iNiR also ships `kdeglobals`, `darklyrc` and `Kvantum/` — Qt/KDE theming. None of
it is carried over, for the same reason `40-environment.kdl` no longer sets
`QT_QPA_PLATFORMTHEME` or `QT_STYLE_OVERRIDE`: the packages those files
configure are not installed. Dolphin renders in Qt's default style. Copying the
theming files without `darkly` and `kvantum` present would configure nothing and
only suggest otherwise.
