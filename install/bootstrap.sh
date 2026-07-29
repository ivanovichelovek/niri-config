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
GREETER="regreet"   # regreet | noctalia | tuigreet | none

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \?//'
    cat <<'EOF'

Options:
  --skip-aur         official repos only (no yay, no zen/chrome/noctalia/…)
  --skip-greeter     don't install or enable a display manager
  --skip-link        install packages only, don't touch ~/.config
  --greeter <name>   regreet (default) | noctalia | tuigreet | none
  -h, --help         this text
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-aur)     SKIP_AUR=1; shift ;;
        --skip-greeter) SKIP_GREETER=1; shift ;;
        --skip-link)    SKIP_LINK=1; shift ;;
        --greeter)      GREETER=$2; shift 2 ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

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

TODO=()

echo "user:   $USER_NAME ($USER_HOME)"
echo "config: $REPO_ROOT"
echo "greeter: $([[ $SKIP_GREETER == 1 ]] && echo "skipped" || echo "$GREETER")"

# ─── packages from the official repos ───────────────────────────────────────
step "Official packages"

PKGS=(
    # compositor + session
    niri xdg-desktop-portal-gtk xdg-desktop-portal-gnome polkit-gnome
    xdg-user-dirs qt6-wayland
    # shell + terminal + editor
    fish kitty neovim micro
    # noctalia runtime deps that live in the official repos
    imagemagick brightnessctl ffmpeg wlr-randr python libqalculate
    # apps
    telegram-desktop nautilus
    # clipboard / screenshot / media
    cliphist wl-clipboard grim slurp
    # audio
    pipewire pipewire-pulse pipewire-alsa wireplumber
    # fonts
    noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-jetbrains-mono-nerd
    # misc
    git curl wget unzip man-db bluez bluez-utils
)

pacman -Syu --needed --noconfirm "${PKGS[@]}"

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
    if as_user command -v yay >/dev/null 2>&1; then
        info "yay already present"
    else
        BUILD_DIR=$(as_user mktemp -d)
        as_user git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$BUILD_DIR/yay-bin"
        # makepkg -si needs to escalate for pacman itself; the invoking user is
        # already in sudoers or this script wouldn't be running.
        ( cd "$BUILD_DIR/yay-bin" && as_user makepkg -si --noconfirm )
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

    for s in lock-and-suspend niri-toggle-gaps; do
        as_user ln -sf "$REPO_ROOT/bin/$s" "$USER_HOME/.local/bin/$s"
    done
    info "helper scripts linked into ~/.local/bin"

    # The config was written on a machine where $HOME was /home/ivanc. Rewrite
    # any absolute paths so it works for whoever is installing it.
    if [[ $USER_HOME != /home/ivanc ]]; then
        mapfile -t HARDCODED < <(grep -rl "/home/ivanc" "$REPO_ROOT/config.kdl" "$REPO_ROOT/config.d" 2>/dev/null || true)
        if [[ ${#HARDCODED[@]} -gt 0 ]]; then
            as_user sed -i "s|/home/ivanc|$USER_HOME|g" "${HARDCODED[@]}"
            info "rewrote /home/ivanc -> $USER_HOME in ${#HARDCODED[@]} file(s)"
        fi
    fi

    # niri-nvim-touchpad is referenced by 90-user-extra.kdl but lives outside
    # this repo — it came from the old dotfiles.
    if [[ ! -x $USER_HOME/.local/bin/niri-nvim-touchpad ]]; then
        warn "~/.local/bin/niri-nvim-touchpad is missing (spawn-at-startup in 90-user-extra.kdl)"
        TODO+=("copy niri-nvim-touchpad into ~/.local/bin, or delete that spawn-at-startup line")
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

        install -d -m 0755 /etc/greetd
        cat >/etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "cage -s -mlast -- regreet"
user = "greeter"
EOF
        cat >/etc/greetd/regreet.toml <<EOF
[background]
path = "/usr/share/noctalia/assets/noctalia-wallpaper.png"
fit = "Cover"

[GTK]
application_prefer_dark_theme = true
cursor_theme_name = "Adwaita"
EOF
        info "wallpaper: /etc/greetd/regreet.toml -> [background] path"
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
