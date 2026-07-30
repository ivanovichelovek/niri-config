#!/usr/bin/env bash
#
# Provision a clean Arch install with niri + noctalia and this config.
#
# Assumes the base system is already there:
#   base base-devel linux linux-firmware linux-headers micro vim grub
#   efibootmgr networkmanager
#
# Run it with sudo, from your normal user account:
#
#   sudo ./install/bootstrap.sh
#
# Everything user-facing (AUR builds, shell change, symlinks) is done as the
# user who invoked sudo — never as root. AUR packages CANNOT be built as root,
# so this script refuses to run without $SUDO_USER.
#
set -euo pipefail

# ─── options ────────────────────────────────────────────────────────────────
SKIP_AUR=0
SKIP_GREETER=0
SKIP_LINK=0
SKIP_WALLPAPERS=0
GREETER="regreet"   # regreet | noctalia | tuigreet | none

usage() {
    sed -n '2,16p' "$0" | sed 's/^# \?//'
    cat <<'EOF'

Options:
  --skip-aur         official repos only (no yay, no zen/chrome/noctalia/…)
  --skip-greeter     don't install or enable a display manager
  --skip-link        install packages only, don't touch ~/.config
  --skip-wallpapers  don't copy wallpapers/ into ~/Pictures/Wallpapers
  --greeter <name>   regreet (default) | noctalia | tuigreet | none
  -h, --help         this text
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-aur)     SKIP_AUR=1; shift ;;
        --skip-greeter) SKIP_GREETER=1; shift ;;
        --skip-link)    SKIP_LINK=1; shift ;;
        --skip-wallpapers) SKIP_WALLPAPERS=1; shift ;;
        --greeter)      GREETER=${2:?--greeter needs a value}; shift 2 ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

# Validate up front — otherwise a typo here is only caught after every package
# is installed and the login shell has already been changed.
case $GREETER in
    regreet|noctalia|tuigreet|none) ;;
    *) echo "unknown greeter: $GREETER (regreet|noctalia|tuigreet|none)" >&2; exit 1 ;;
esac

# ─── preconditions ──────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || { echo "run this with sudo: sudo $0" >&2; exit 1; }

if [[ -z ${SUDO_USER:-} || $SUDO_USER == root ]]; then
    echo "SUDO_USER is not set — run this as 'sudo $0' from your normal user," >&2
    echo "not from a root shell. AUR packages cannot be built as root." >&2
    exit 1
fi

command -v pacman >/dev/null || { echo "pacman not found — this is not Arch" >&2; exit 1; }

USER_NAME=$SUDO_USER
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
[[ -d $USER_HOME ]] || { echo "home directory for $USER_NAME not found" >&2; exit 1; }

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
[[ -f $REPO_ROOT/config.kdl ]] || { echo "config.kdl not found in $REPO_ROOT" >&2; exit 1; }

step()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info()  { printf '    %s\n' "$*"; }
warn()  { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
as_user() { sudo -u "$USER_NAME" HOME="$USER_HOME" "$@"; }

# Point ~/.config/<name> at dots/<name>. An existing real directory is moved
# aside rather than deleted — this script must never lose someone's config.
link_dot() {
    local name=$1 dst="$USER_HOME/.config/$1"
    if [[ -e $dst && ! -L $dst ]]; then
        local backup="$dst.bak.$(date +%Y%m%d%H%M%S)"
        warn "$dst exists — moving it to $backup"
        as_user mv "$dst" "$backup"
    elif [[ -L $dst ]]; then
        rm -f "$dst"
    fi
    as_user ln -s "$REPO_ROOT/dots/$name" "$dst"
}

TODO=()

echo "user:   $USER_NAME ($USER_HOME)"
echo "config: $REPO_ROOT"
echo "greeter: $([[ $SKIP_GREETER == 1 ]] && echo "skipped" || echo "$GREETER")"

# ─── packages from the official repos ───────────────────────────────────────
step "Official packages"

PKGS=(
    # ── drivers / firmware for this machine ─────────────────────────────────
    # Ryzen 7 5800U (Cezanne). Microcode is NOT part of base — without it the
    # CPU runs on shipped-in-silicon errata. GRUB is regenerated below so the
    # microcode image is actually loaded.
    amd-ucode
    # GPU: integrated Radeon Vega (amdgpu). A base install has no GPU userspace.
    # On Intel swap vulkan-radeon -> vulkan-intel; on NVIDIA use
    # nvidia-open-dkms + egl-wayland instead.
    mesa vulkan-radeon
    # Audio. alsa-ucm-conf only, deliberately NOT sof-firmware: on this laptop
    # sound runs through snd_hda_intel and the Audio Coprocessor at 04:00.5 has
    # no driver bound at all. Installing sof-firmware can make the kernel bind
    # snd_sof_amd_renoir to it and move audio onto the SOF path, which is a way
    # to break working sound rather than fix anything. Install it only if the
    # internal mic or speakers turn out to be dead.
    alsa-ucm-conf
    # Ethernet (Realtek RTL8111, r8169), Wi-Fi (RTL8822CE, rtw88) and the
    # RTL8822CE bluetooth radio are all in-kernel; their firmware comes from
    # linux-firmware, which the base install already has.
    #
    # Laptop power profiles — also an optional dependency of noctalia.
    power-profiles-daemon
    # Not installed by default: fprintd (FocalTech 2808:c652 fingerprint
    # reader). Support for that model is patchy — install it yourself if wanted.
    # compositor + session
    niri xdg-desktop-portal-gtk xdg-desktop-portal-gnome polkit-gnome
    xdg-user-dirs qt6-wayland
    # X11 apps. Two independent things need this:
    #   - Happ bundles Qt 6.5, ignores QT_QPA_PLATFORM and always loads the xcb
    #     platform plugin, so it aborts without an X server. niri 26.04 has a
    #     native `xwayland-satellite` node (see config.kdl) that starts the
    #     rootless server and exports DISPLAY.
    #   - cage (which runs regreet) is built against a wlroots with XWayland
    #     support and EXITS if /usr/bin/Xwayland is missing. xorg-xwayland is
    #     neither a hard nor an optional dependency of cage, so pacman never
    #     pulls it in: on a clean install the greeter would crash-loop with
    #     "Cannot create XWayland server".
    xorg-xwayland xwayland-satellite xcb-util-cursor
    # shell + terminal + editor (starship and eza are used by dots/fish)
    fish kitty neovim micro starship eza
    # noctalia runtime deps that live in the official repos
    imagemagick brightnessctl ffmpeg wlr-randr python libqalculate
    # bin/random-wallpaper is a GTK4 app (no libadwaita — it ships its own
    # theme); it talks to both wallpaper APIs with stdlib urllib.
    python-gobject gtk4 librsvg
    # apps
    telegram-desktop nautilus
    # clipboard / screenshot / media
    cliphist wl-clipboard grim slurp
    # night-light — bin/wlsunset-restart drives it, bin/lock-and-suspend calls that
    wlsunset
    # audio
    pipewire pipewire-pulse pipewire-alsa wireplumber
    # fonts
    noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-jetbrains-mono-nerd
    # misc
    git curl wget unzip man-db bluez bluez-utils
)

pacman -Syu --needed --noconfirm "${PKGS[@]}"

# amd-ucode only takes effect once it is referenced from the boot entry.
if command -v grub-mkconfig >/dev/null && [[ -d /boot/grub ]]; then
    step "Regenerating GRUB config (picks up amd-ucode)"
    grub-mkconfig -o /boot/grub/grub.cfg
else
    warn "GRUB not found — microcode will not load until your bootloader references it"
    TODO+=("add the amd-ucode initrd to your boot entry")
fi

# ─── AUR ────────────────────────────────────────────────────────────────────
AUR_PKGS=(
    noctalia-git        # the shell (v5, native C++ — does NOT need quickshell)
    zen-browser-bin     # zen
    google-chrome
    yandex-music
    happ-desktop-bin
)

if [[ $SKIP_AUR == 1 ]]; then
    warn "AUR skipped — noctalia, zen, chrome, yandex-music and happ NOT installed"
    TODO+=("install AUR packages later: yay -S ${AUR_PKGS[*]}")
else
    step "AUR helper (yay)"
    # NOTE: `command` is a shell builtin, so `sudo -u user command -v yay` always
    # fails. Check as root instead — /usr/bin is on root's PATH too.
    if command -v yay >/dev/null 2>&1; then
        info "yay already present"
    else
        BUILD_DIR=$(as_user mktemp -d)
        as_user git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$BUILD_DIR/yay-bin"
        # Build as the user (makepkg refuses to run as root), then install as
        # root ourselves. Using `makepkg -si` would make makepkg call `sudo
        # pacman` from inside a sudo session, which can block on a password
        # prompt if the timestamp expires during a long build.
        ( cd "$BUILD_DIR/yay-bin" && as_user makepkg -s --noconfirm )
        pacman -U --noconfirm "$BUILD_DIR"/yay-bin/yay-bin-*.pkg.tar.*
        rm -rf "$BUILD_DIR"
    fi

    step "AUR packages"
    info "${AUR_PKGS[*]}"
    # --sudoloop keeps the sudo timestamp alive across long builds.
    as_user yay -S --needed --noconfirm --sudoloop "${AUR_PKGS[@]}" || {
        warn "one or more AUR packages failed to build"
        TODO+=("re-run: yay -S ${AUR_PKGS[*]}")
    }
fi

# ─── shell ──────────────────────────────────────────────────────────────────
step "Login shell"
CURRENT_SHELL=$(getent passwd "$USER_NAME" | cut -d: -f7)
if [[ $CURRENT_SHELL == /usr/bin/fish ]]; then
    info "already fish"
else
    chsh -s /usr/bin/fish "$USER_NAME"
    info "$CURRENT_SHELL -> /usr/bin/fish"
fi

# ─── config ─────────────────────────────────────────────────────────────────
if [[ $SKIP_LINK == 1 ]]; then
    warn "config linking skipped"
else
    step "niri config"

    NIRI_CFG="$USER_HOME/.config/niri"
    as_user mkdir -p "$USER_HOME/.config" "$USER_HOME/.local/bin"

    if [[ -e $NIRI_CFG && ! -L $NIRI_CFG ]]; then
        BACKUP="$NIRI_CFG.bak.$(date +%Y%m%d%H%M%S)"
        warn "$NIRI_CFG exists and is a real directory — moving it to $BACKUP"
        as_user mv "$NIRI_CFG" "$BACKUP"
    elif [[ -L $NIRI_CFG ]]; then
        info "replacing existing symlink"
        rm -f "$NIRI_CFG"
    fi
    as_user ln -s "$REPO_ROOT" "$NIRI_CFG"
    info "$NIRI_CFG -> $REPO_ROOT"

    for s in lock-and-suspend niri-toggle-gaps niri-nvim-touchpad wlsunset-restart \
             random-wallpaper; do
        as_user ln -sf "$REPO_ROOT/bin/$s" "$USER_HOME/.local/bin/$s"
    done
    info "helper scripts linked into ~/.local/bin"

    # Desktop entries, so the shell launcher can find random-wallpaper too.
    as_user mkdir -p "$USER_HOME/.local/share/applications"
    for d in "$REPO_ROOT"/share/applications/*.desktop; do
        as_user ln -sf "$d" "$USER_HOME/.local/share/applications/$(basename "$d")"
    done
    as_user update-desktop-database "$USER_HOME/.local/share/applications" 2>/dev/null || true
    info "desktop entries linked into ~/.local/share/applications"

    ICON_DIR="$USER_HOME/.local/share/icons/hicolor/scalable/apps"
    as_user mkdir -p "$ICON_DIR"
    for i in "$REPO_ROOT"/share/icons/hicolor/scalable/apps/*.svg; do
        as_user ln -sf "$i" "$ICON_DIR/$(basename "$i")"
    done
    as_user gtk-update-icon-cache -qtf "$USER_HOME/.local/share/icons/hicolor" 2>/dev/null || true
    info "app icons linked into ~/.local/share/icons"

    # The config was written on a machine where $HOME was /home/ivanc. Rewrite
    # any absolute paths so it works for whoever is installing it. dots/ is
    # included: noctalia's settings.toml points at wallpapers by absolute path,
    # Happ's routing.json at an asset directory, and gp8.fish at a wine prefix.
    #
    # This edits tracked files, so `git status` in the repo will show them as
    # modified afterwards. That is expected on a machine with a different
    # username, and there is nothing to commit back.
    if [[ $USER_HOME != /home/ivanc ]]; then
        mapfile -t HARDCODED < <(grep -rl "/home/ivanc" "$REPO_ROOT/config.kdl" \
            "$REPO_ROOT/config.d" "$REPO_ROOT/share" "$REPO_ROOT/dots" \
            "$REPO_ROOT/bin" 2>/dev/null || true)
        if [[ ${#HARDCODED[@]} -gt 0 ]]; then
            as_user sed -i "s|/home/ivanc|$USER_HOME|g" "${HARDCODED[@]}"
            info "rewrote /home/ivanc -> $USER_HOME in ${#HARDCODED[@]} file(s)"
        fi
    fi

    if command -v niri >/dev/null; then
        if as_user niri validate -c "$REPO_ROOT/config.kdl" >/dev/null 2>&1; then
            info "niri validate: config is valid"
        else
            warn "niri validate FAILED — run 'niri validate' and fix before logging in"
            TODO+=("fix niri config errors (niri validate)")
        fi
    fi

    as_user mkdir -p "$USER_HOME/Pictures/Wallpapers" "$USER_HOME/Pictures/Screenshots"

    step "fish config"
    link_dot fish
    info "$USER_HOME/.config/fish -> $REPO_ROOT/dots/fish"

    # Secrets are deliberately not in the repo.
    if [[ ! -f $REPO_ROOT/dots/fish/conf.d/secrets.fish ]]; then
        info "no secrets.fish — copy conf.d/secrets.fish.example if you need API keys"
        TODO+=("create ~/.config/fish/conf.d/secrets.fish from the .example (gitignored)")
    fi

    # fish_variables references fisher; the plugin manager itself is not a
    # pacman package and installs from inside fish.
    TODO+=("optional: install fisher — curl -sL https://git.io/fisher | source && fisher update")

    step "kitty config"
    # Only kitty.conf is symlinked, not the whole directory: noctalia renders
    # themes/noctalia.conf into ~/.config/kitty on every wallpaper change, and
    # that generated file has no business in the repo.
    KITTY_CFG="$USER_HOME/.config/kitty"
    # An earlier version of this script symlinked the whole directory. Drop that
    # link FIRST: otherwise every path below resolves inside the repo, and the
    # tracked kitty.conf gets moved aside and replaced by a symlink to itself.
    if [[ -L $KITTY_CFG ]]; then
        rm -f "$KITTY_CFG"
        info "replaced the old whole-directory symlink"
    fi
    as_user mkdir -p "$KITTY_CFG/themes"
    if [[ -f $KITTY_CFG/kitty.conf && ! -L $KITTY_CFG/kitty.conf ]]; then
        as_user mv "$KITTY_CFG/kitty.conf" "$KITTY_CFG/kitty.conf.bak.$(date +%Y%m%d%H%M%S)"
    fi
    as_user ln -sf "$REPO_ROOT/dots/kitty/kitty.conf" "$KITTY_CFG/kitty.conf"
    # Seed the palette so the terminal has colours before noctalia first runs
    # its template; noctalia overwrites this file, never the repo.
    if [[ ! -f $KITTY_CFG/themes/noctalia.conf ]]; then
        as_user cp "$REPO_ROOT/dots/kitty/theme.conf" "$KITTY_CFG/themes/noctalia.conf"
    fi
    info "$KITTY_CFG/kitty.conf -> $REPO_ROOT/dots/kitty/kitty.conf"
    TODO+=("enable the kitty template in noctalia settings so colours follow the wallpaper")

    step "neovim (LVim)"
    NVIM_CFG="$USER_HOME/.config/nvim"
    if [[ -e $NVIM_CFG ]]; then
        info "$NVIM_CFG already exists — left alone"
    elif as_user git clone --quiet https://github.com/ivanovichelovek/LVim.git "$NVIM_CFG"; then
        info "cloned LVim into $NVIM_CFG"
        # Cloned over https so it works before any SSH key exists; switch the
        # remote to ssh so pushing works once the key is in place.
        as_user git -C "$NVIM_CFG" remote set-url origin \
            git@github.com:ivanovichelovek/LVim.git
        as_user git -C "$NVIM_CFG" remote add upstream \
            https://github.com/LazyVim/LazyVim.git 2>/dev/null || true
        TODO+=("first 'nvim' run installs plugins — needs network, takes a minute")
    else
        warn "could not clone LVim"
        TODO+=("clone https://github.com/ivanovichelovek/LVim.git into ~/.config/nvim")
    fi

    step "app configs"
    # Both are copied, not symlinked: the apps rewrite these files themselves.
    # -n so a re-run never overwrites settings changed since the install.

    # noctalia keeps its state here, not in ~/.config/noctalia (which stays
    # empty unless you add user overrides).
    # `cp -n` exits 0 whether or not it copied, so test first rather than
    # reporting from its status.
    as_user mkdir -p "$USER_HOME/.local/state/noctalia"
    NOCTALIA_SETTINGS="$USER_HOME/.local/state/noctalia/settings.toml"
    if [[ -f $NOCTALIA_SETTINGS ]]; then
        info "noctalia settings already present — left alone"
    else
        as_user cp "$REPO_ROOT/dots/noctalia/settings.toml" "$NOCTALIA_SETTINGS"
        info "noctalia settings seeded"
    fi

    # Happ: the sing-box config and the routing rules only. subs.db holds the
    # server subscriptions — credentials — and is gitignored, so it has to be
    # re-added by hand from the app.
    as_user mkdir -p "$USER_HOME/.config/Happ"
    for j in "$REPO_ROOT"/dots/happ/*.json; do
        if [[ -f "$USER_HOME/.config/Happ/$(basename "$j")" ]]; then
            info "Happ/$(basename "$j") already present — left alone"
        else
            as_user cp "$j" "$USER_HOME/.config/Happ/"
            info "Happ/$(basename "$j") copied"
        fi
    done
    TODO+=("re-add your Happ subscriptions — subs.db is not in the repo")

    step "wallpapers"
    if [[ $SKIP_WALLPAPERS == 1 ]]; then
        info "skipped (--skip-wallpapers)"
    elif [[ -d $REPO_ROOT/wallpapers ]]; then
        # -n so a re-run never clobbers wallpapers added since the last install.
        as_user cp -rn "$REPO_ROOT"/wallpapers/. "$USER_HOME/Pictures/Wallpapers/"
        info "$(find "$REPO_ROOT/wallpapers" -type f | wc -l) wallpaper(s) -> ~/Pictures/Wallpapers"
    else
        warn "no wallpapers/ directory in the repo"
    fi
fi

# ─── greeter ────────────────────────────────────────────────────────────────
if [[ $SKIP_GREETER == 1 || $GREETER == none ]]; then
    warn "no display manager — log in on tty1 and run 'niri' by hand"
else
    step "Greeter ($GREETER)"

    case $GREETER in
    regreet)
        # greetd itself is a tiny daemon (~1-2 MB resident); the greeter process
        # only lives until you log in. cage is the one-window compositor it runs in.
        pacman -S --needed --noconfirm greetd greetd-regreet cage
        # cage exits without this; see the PKGS comment above.
        if [[ ! -x /usr/bin/Xwayland ]]; then
            warn "/usr/bin/Xwayland missing — cage will crash-loop"
            pacman -S --needed --noconfirm xorg-xwayland
        fi

        install -d -m 0755 /etc/greetd
        cat >/etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "cage -s -- regreet"
user = "greeter"
EOF
        # regreet writes its state here; the package does not always create it.
        if getent passwd greeter >/dev/null; then
            install -d -o greeter -g greeter -m 0755 /var/cache/regreet /var/log/regreet
        else
            warn "user 'greeter' does not exist — greetd package may have failed"
            TODO+=("check that greetd created the 'greeter' user")
        fi

        # Only point at a wallpaper that actually exists, otherwise regreet
        # logs an error on every boot.
        WALL=/usr/share/noctalia/assets/noctalia-wallpaper.png
        {
            if [[ -f $WALL ]]; then
                printf '[background]\npath = "%s"\nfit = "Cover"\n\n' "$WALL"
            fi
            printf '[GTK]\napplication_prefer_dark_theme = true\ncursor_theme_name = "Adwaita"\n'
        } >/etc/greetd/regreet.toml

        if [[ -f $WALL ]]; then
            info "wallpaper: $WALL (change it in /etc/greetd/regreet.toml)"
        else
            warn "no wallpaper set — noctalia assets not found (installed with --skip-aur?)"
            TODO+=("set [background] path in /etc/greetd/regreet.toml")
        fi
        ;;
    tuigreet)
        pacman -S --needed --noconfirm greetd greetd-tuigreet
        install -d -m 0755 /etc/greetd
        cat >/etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --cmd niri"
user = "greeter"
EOF
        warn "tuigreet is text-only — no wallpaper"
        ;;
    noctalia)
        pacman -S --needed --noconfirm greetd
        as_user yay -S --needed --noconfirm --sudoloop noctalia-greeter || {
            warn "noctalia-greeter failed to build"
            TODO+=("install a greeter manually, or re-run with --greeter regreet")
        }
        install -d -m 0755 /etc/greetd
        cat >/etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "noctalia-greeter"
user = "greeter"
EOF
        info "noctalia-greeter bundles its own wlroots compositor — no cage needed"
        ;;
    *)
        echo "unknown greeter: $GREETER" >&2; exit 1 ;;
    esac

    # Virtual GPUs (vmwgfx under VirtualBox/VMware, and qxl) cannot hand wlroots
    # a buffer for scanout with modifiers: cage dies with "Failed to get buffer
    # handle for plane 0: Invalid argument" and greetd restarts it forever.
    # Software rendering costs nothing on a login screen.
    VIRT=$(systemd-detect-virt 2>/dev/null || echo none)
    if [[ $VIRT != none && $GREETER != tuigreet ]]; then
        install -d -m 0755 /etc/systemd/system/greetd.service.d
        cat >/etc/systemd/system/greetd.service.d/10-virtual-gpu.conf <<'EOF'
# Written by install/bootstrap.sh because this machine is a VM.
# Delete this file on real hardware.
[Service]
Environment=WLR_RENDERER=pixman
Environment=WLR_DRM_NO_MODIFIERS=1
Environment=WLR_NO_HARDWARE_CURSORS=1
EOF
        info "$VIRT detected — greetd will use software rendering"
    fi

    systemctl enable greetd.service
    info "enabled greetd.service — disable it any time with: systemctl disable greetd"
fi

# ─── services ───────────────────────────────────────────────────────────────
step "Services"
systemctl enable NetworkManager.service
systemctl enable bluetooth.service
info "NetworkManager, bluetooth enabled"

as_user xdg-user-dirs-update || true

# ─── done ───────────────────────────────────────────────────────────────────
step "Done"

cat <<EOF

  Installed for: $USER_NAME
  niri config:   ~/.config/niri -> $REPO_ROOT
  shell:         fish
  greeter:       $([[ $SKIP_GREETER == 1 ]] && echo "none" || echo "$GREETER")

  Workspaces and their apps (see config.d/90-user-extra.kdl):
    term   kitty
    web    zen, google-chrome
    chat   telegram
    code   nvim  (kitty --class nvim)
    music  yandex-music
    vpn    happ

EOF

if [[ ${#TODO[@]} -gt 0 ]]; then
    printf '\033[1;33m  Still to do:\033[0m\n'
    for t in "${TODO[@]}"; do printf '    - %s\n' "$t"; done
    echo
fi

cat <<'EOF'
  Verify app-ids once everything is running — window rules match on them:

    niri msg windows

  'happ' in particular is a guess: happ-desktop-bin ships no .desktop file.
  Fix the rule in config.d/90-user-extra.kdl if the real app-id differs.
EOF
