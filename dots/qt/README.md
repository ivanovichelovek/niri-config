# qt

Qt/KDE theming, so Qt apps follow the session instead of falling back to their
own default styling. Taken from [iNiR](https://github.com/snowarch/iNiR)
(`dots/.config/darklyrc` and `dots/.config/Kvantum/` there).

Copied rather than symlinked by `install/bootstrap.sh`: these apps rewrite their
own settings files. `cp -n`, so a re-run never overwrites yours.

## What makes it work

| piece | where |
|---|---|
| `QT_QPA_PLATFORMTHEME "kde"` | `config.d/40-environment.kdl` |
| `QT_STYLE_OVERRIDE "Darkly"` | same |
| `plasma-integration`, `kde-cli-tools`, `kvantum` | `PKGS` in the installer |
| `darkly-bin` | `AUR_PKGS` |

Without those packages both variables are ignored and Qt apps look untouched —
the pair is only as good as what backs it. `kde-cli-tools` is the one that is
easy to miss: under this platform theme it backs the file dialogs and the "Open
With" window, and iNiR hit exactly that (#144 in its changelog).

The active style is **Darkly**. Kvantum is installed and configured
(`theme=MaterialAdw`) but not in use, since `QT_STYLE_OVERRIDE` wins — it is
here for when you want to switch.

## Colours: not iNiR's kdeglobals

iNiR ships a `kdeglobals` with a hardcoded palette that matugen generated from
the wallpaper. That file is **deliberately not carried over**. Noctalia does the
same job through its `kcolorscheme` builtin template, enabled in
`dots/noctalia/settings.toml`: it renders
`~/.local/share/color-schemes/noctalia.colors` and applies it, so KDE apps track
the wallpaper like kitty and Telegram already do. A static `kdeglobals` would be
wrong from the first wallpaper change onwards.

Verified on this machine: `kdeglobals` came out with `BackgroundNormal=16,20,24`,
which is `#101418` — the same background kitty's generated theme carries.

## The file manager is nautilus

This directory is not about a file manager. The bind in `70-binds.kdl` spawns
`nautilus`, which is what iNiR itself uses. Dolphin was tried here and reverted;
if you want it, that is what `config.d/99-local.kdl` is for — see the README's
"Local overrides". Its own `dolphinrc` and `kservicemenurc` are not tracked in
this repo.
