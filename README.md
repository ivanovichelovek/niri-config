# niri-config

Standalone [niri](https://github.com/YaLTeR/niri) configuration, extracted from
an iNiR (Quickshell) setup and adapted for the [Noctalia](https://noctalia.dev)
shell. No dependency on iNiR, illogical-impulse or Quickshell remains.

## Install

On a clean Arch system, `install/bootstrap.sh` does all of this for you —
packages, AUR helper, fish as login shell, greeter, symlinks:

```fish
git clone git@github.com:ivanovichelovek/niri-config.git ~/GitHub/niri-config
cd ~/GitHub/niri-config
sudo ./install/bootstrap.sh
```

By hand instead:

```fish
git clone git@github.com:ivanovichelovek/niri-config.git ~/GitHub/niri-config
ln -s ~/GitHub/niri-config ~/.config/niri

# helper scripts referenced by binds
mkdir -p ~/.local/bin
ln -s ~/GitHub/niri-config/bin/*  ~/.local/bin/
ln -s ~/GitHub/niri-config/dots/fish   ~/.config/fish
ln -s ~/GitHub/niri-config/dots/kitty  ~/.config/kitty

niri validate            # should print "config is valid"
```

Requires: `niri`, `noctalia`, `kitty`, `fish`, `zen-browser`, `google-chrome`,
`telegram-desktop`, `yandex-music`, `happ-desktop-bin`, `nautilus`, `cliphist`,
`wl-clipboard`, and a polkit agent — `bootstrap.sh` installs all of them.

All helper scripts live in `bin/` and are symlinked into `~/.local/bin`:
`lock-and-suspend`, `niri-toggle-gaps`, `random-wallpaper`, `niri-nvim-touchpad`
(spawned by `config.d/90-user-extra.kdl`) and `wlsunset-restart` (called by
`lock-and-suspend`).

`--skip-wallpapers` leaves `~/Pictures/Wallpapers` alone; otherwise the 28
images in `wallpapers/` are copied there. The copy uses `cp -n`, so re-running
the script never overwrites anything you have added since.

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
| `90-user-extra.kdl` | named workspaces + per-app assignment + personal binds |

The two files carrying the app automation — `30-window-rules.kdl` and
`90-user-extra.kdl` — are compositor config and needed no conversion when
moving off iNiR.
Noctalia has no equivalent for them and never will: it is a layer-shell client
and does not manage windows.

## Random wallpaper

`bin/random-wallpaper` — a GTK4 app on `Ctrl+Alt+W`, or "Random Wallpaper" in
the launcher. It downloads one random image, shows it full-size, and waits:

| key | button | effect |
|---|---|---|
| `S` / `Return` | Save | move it into `~/random_wallpaper/`, then fetch the next |
| `D` / `Delete` | Delete | unlink the download and close |
| `N` / `Space` | Next | discard this one, fetch another |
| `Esc` | — | close; the unsaved download is discarded |

Sources are Konachan (`rating:safe`) and Wallhaven (`purity=100`,
`categories=110`), switchable in the header bar. `--source konachan|wallhaven`
picks the startup one.

`~/random_wallpaper` is hardcoded and created on first save. **Saving cannot
destroy an earlier wallpaper**: downloads live in `~/.cache/random-wallpaper`
until you accept one, and the save path is uniquified (`-2`, `-3`, …) rather
than overwritten. This is the one thing iNiR's `random_konachan_wall.sh` got
wrong — it wrote every download to the same `random_wallpaper.jpg`.

Every save is also hardlinked into `~/Pictures/Wallpapers` — that is the
directory Noctalia's picker and `wallpaper-random` scan, and `~/random_wallpaper`
is not. Same filesystem, so the link costs no extra space, and the name is
uniquified there too. Deleting from one place leaves the other copy.

"Set as wallpaper on save" calls `noctalia msg wallpaper-set`. If that fails
the toast says so, but the file is still saved.

`tests/test-random-wallpaper.py` asserts the non-destructive properties against
a throwaway `$HOME` (needs network — it does one real download per source).

The osu! seasonal-backgrounds endpoint the old script used now returns 403 —
it moved behind OAuth — so Wallhaven replaced it.

## fish

`dots/fish` is the shell config; `bootstrap.sh` symlinks it to `~/.config/fish`.
Needs `starship` and `eza`, both installed by the script.

**Secrets are not in this repo.** `config.fish` sources
`~/.config/fish/conf.d/secrets.fish`, which is gitignored — copy
`dots/fish/conf.d/secrets.fish.example` and fill it in. Never put a key in a
tracked file; removing it in a later commit does not remove it from history.

## Neovim

`bootstrap.sh` clones [LVim](https://github.com/ivanovichelovek/LVim) (a LazyVim
fork) into `~/.config/nvim` over https, then switches `origin` to ssh and adds
`upstream` pointing at LazyVim. It skips the clone if `~/.config/nvim` already
exists. The first `nvim` run installs plugins and needs network.

## kitty

`dots/kitty` is symlinked to `~/.config/kitty`. `kitty.conf` carries the
JetBrains Mono Nerd Font setting, the 21.75px margin and
`background_opacity 0.85` — if the terminal is opaque, this symlink is missing.

`kitty.conf` includes `current-theme.conf`, which Noctalia's template system
overwrites on every wallpaper change; it is gitignored and seeded from the
tracked `theme.conf` at install time.

`ctrl+f` maps to a `search.py` kitten that is not shipped here — the binding
does nothing until you drop that kitten into `~/.config/kitty`.

## Hardware

The driver list in `bootstrap.sh` targets a Ryzen 7 5800U laptop: `amd-ucode`
(microcode is *not* part of `base`), `mesa` + `vulkan-radeon` for the integrated
Vega, `sof-firmware` + `alsa-ucm-conf` for the Renoir/Cezanne audio coprocessor.
Ethernet (RTL8111), Wi-Fi (RTL8822CE) and its bluetooth radio are in-kernel and
covered by `linux-firmware`. GRUB is regenerated after install so the microcode
image is actually loaded.

On other hardware, edit the block at the top of `PKGS`: `vulkan-intel` for Intel,
`nvidia-open-dkms` + `egl-wayland` for NVIDIA.

## Workspaces

Six named workspaces, always present, with apps assigned on open:

| workspace | app | `app-id` |
|---|---|---|
| `term` | kitty | `kitty` (excluding `remind-*` titles) |
| `web` | Zen | `^zen(-browser)?$` |
| `web` | Google Chrome | `google-chrome` |
| `chat` | Telegram | `org.telegram.desktop` |
| `code` | Neovim | `nvim` (kitty `--class nvim`) |
| `music` | Yandex Music | `YandexMusic` |
| `vpn` | Happ | `(?i)^happ$` — **unverified**, see below |

All except the terminal open maximized. `Mod+1`…`Mod+6` focus them in that order.

Every app-id above was read off the installed `.desktop` file except **Happ**:
`happ-desktop-bin` ships none (its binary is `/opt/happ/bin/Happ`), so the rule
is a case-insensitive guess. Confirm with `niri msg windows` once it's running
and pin the exact value.

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
| `Ctrl+Alt+W` | random wallpaper previewer *(new)* |

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
