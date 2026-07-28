# niri-config

Standalone [niri](https://github.com/YaLTeR/niri) configuration, extracted from
an iNiR (Quickshell) setup and adapted for the [Noctalia](https://noctalia.dev)
shell. No dependency on iNiR, illogical-impulse or Quickshell remains.

## Install

```fish
git clone <this-repo> ~/GitHub/niri-config
ln -s ~/GitHub/niri-config ~/.config/niri

# helper scripts referenced by binds
mkdir -p ~/.local/bin
ln -s ~/GitHub/niri-config/bin/lock-and-suspend  ~/.local/bin/
ln -s ~/GitHub/niri-config/bin/niri-toggle-gaps  ~/.local/bin/

niri validate            # should print "config is valid"
```

Requires: `niri`, `noctalia`, `kitty`, `zen-browser`, `nautilus`, `cliphist`,
`wl-clipboard`, and a polkit agent. `wlsunset-restart` is referenced by
`bin/lock-and-suspend` and is not included here.

## Layout

| file | status |
|---|---|
| `10-input-and-cursor.kdl` | unchanged |
| `20-layout-and-overview.kdl` | unchanged (comment wording only) |
| `30-window-rules.kdl` | **unchanged** — per-app window rules |
| `40-environment.kdl` | iNiR venv + Quickshell logging vars dropped |
| `50-startup.kdl` | starts `noctalia -d` instead of `inir.service` |
| `60-animations.kdl` | unchanged (comment wording only) |
| `70-binds.kdl` | 37 iNiR binds re-pointed at `noctalia msg` |
| `80-layer-rules.kdl` | `quickshell:*Backdrop` → `noctalia-wallpaper` |
| `90-user-extra.kdl` | **unchanged** — named workspaces + per-app assignment |

The two files carrying the app automation — `30-window-rules.kdl` and
`90-user-extra.kdl` — are compositor config and needed no conversion at all.
Noctalia has no equivalent for them and never will: it is a layer-shell client
and does not manage windows.

## Workspaces

Six named workspaces, always present, with apps assigned on open:

| workspace | app | `app-id` |
|---|---|---|
| `term` | kitty | `kitty` (excluding `remind-*` titles) |
| `web` | Zen | `zen` |
| `chat` | AyuGram | `com.ayugram.desktop` |
| `code` | Neovim | `nvim` (kitty `--class nvim`) |
| `music` | Yandex Music | `YandexMusic` |
| `vpn` | Nekobox | `nekobox` |

All except the terminal open maximized. `Mod+1`…`Mod+6` focus them in that order.

## Shell binds

Noctalia cannot grab global keys — it is a layer-shell client, so the compositor
owns every shortcut and forwards it over IPC. Bind keys here; run
`noctalia msg --help` for the command list.

| key | action |
|---|---|
| `Mod+Space` | app launcher |
| `Mod+V` | clipboard panel |
| `Mod+Shift+C` | control center *(new)* |
| `Mod+Comma` | shell settings |
| `Mod+Shift+Q` | session / power |
| `Ctrl+Alt+T` | wallpaper picker |
| `Mod+Shift+S` | region screenshot |
| `Mod+Ctrl+S` | fullscreen screenshot *(new)* |
| `Mod+Alt+L` | lock |
| `Mod+Slash` | niri hotkey cheatsheet *(was iNiR's own)* |
| `Alt+Tab` | window switcher |

Volume, brightness and media keys route through `noctalia msg` for OSD feedback.

## Dropped — no Noctalia equivalent

Left commented in place in `70-binds.kdl`:

- `Alt+Shift+Tab` — `window-switcher` has no reverse direction
- `Mod+Shift+X` — region OCR (see AUR `noctalia-plugin-screenshot-ocr`)
- `Mod+Shift+A` — region Google Lens search
- `Mod+Shift+R` — screen recording with sound (bind `wf-recorder` if wanted)
- `Super+G` — crosshair overlay
- `Mod+Shift+W` — iNiR panel-family cycle

`Mod+Q` now uses niri's native `close-window`; iNiR wrapped it in a confirmation
dialog for unsaved work, which Noctalia does not have.

## Verify on a new system

```fish
niri validate
niri msg layers          # confirm noctalia-wallpaper / noctalia-bar-default
noctalia config validate
```

Two things in `50-startup.kdl` may be redundant under Noctalia and are flagged
in comments there: the `cliphist` watchers (Noctalia keeps its own clipboard
store) and the external polkit agent (Noctalia has a polkit panel).
