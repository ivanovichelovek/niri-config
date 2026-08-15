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
ASSUME_YES=0        # 1: never ask, do every step (set by --yes or "yes for all")
GREETER="regreet"   # regreet | noctalia | tuigreet | none
USER_NAME=""        # empty: ask, defaulting to $SUDO_USER
# Drivers. Empty means detect from the hardware (see "hardware" below); the
# flags exist to override a wrong guess — and to exercise the Intel and NVIDIA
# paths on a machine that has neither.
CPU_VENDOR=""       # empty: detect. amd | intel | none
GPU_VENDORS=""      # empty: detect. comma-separated: amd,intel,nvidia,none
# The image set lives in its own repository, not in a branch here: `git clone`
# fetches every branch, so images on a branch next to the config would have
# ridden along with every clone anyway.
WALLPAPER_REPO="https://github.com/ivanovichelovek/niri-wallpapers.git"

usage() {
    sed -n '2,16p' "$0" | sed 's/^# \?//'
    cat <<'EOF'

Every step asks before it runs; the first question offers "yes for all" to
answer them in one go. Answering no to a step skips it and moves on.

Options:
  -y, --yes          don't ask anything, run every step (for unattended runs)
                     the NVIDIA driver is the one exception: it always asks,
                     and is skipped with a TODO when there is no tty
  --skip-aur         official repos only (no yay, no chrome/noctalia/…)
  --skip-greeter     don't install or enable a display manager
  --skip-link        install packages only, don't touch ~/.config
  --skip-wallpapers  don't fetch the wallpaper set
  --greeter <name>   regreet (default) | noctalia | tuigreet | none
  --user <name>      install for this user (default: ask, offering $SUDO_USER)
  --cpu <vendor>     microcode: amd | intel | none (default: detect)
  --gpu <vendors>    GPU userspace: amd | intel | nvidia | none, comma-separated
                     for a hybrid machine (default: detect)
  -h, --help         this text

A --skip-* flag wins over the prompt: that step is never offered.
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-aur)     SKIP_AUR=1; shift ;;
        --skip-greeter) SKIP_GREETER=1; shift ;;
        --skip-link)    SKIP_LINK=1; shift ;;
        --skip-wallpapers) SKIP_WALLPAPERS=1; shift ;;
        -y|--yes)       ASSUME_YES=1; shift ;;
        --greeter)      GREETER=${2:?--greeter needs a value}; shift 2 ;;
        --user)         USER_NAME=${2:?--user needs a value}; shift 2 ;;
        --cpu)          CPU_VENDOR=${2:?--cpu needs a value}; shift 2 ;;
        --gpu)          GPU_VENDORS=${2:?--gpu needs a value}; shift 2 ;;
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

case ${CPU_VENDOR:-detect} in
    detect|amd|intel|none) ;;
    *) echo "unknown --cpu: $CPU_VENDOR (amd|intel|none)" >&2; exit 1 ;;
esac

if [[ -n $GPU_VENDORS ]]; then
    IFS=, read -ra _gpu_check <<<"$GPU_VENDORS"
    for _g in "${_gpu_check[@]}"; do
        case $_g in
            amd|intel|nvidia|none) ;;
            *) echo "unknown --gpu: $_g (amd|intel|nvidia|none)" >&2; exit 1 ;;
        esac
    done
fi

# ─── preconditions ──────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || { echo "run this with sudo: sudo $0" >&2; exit 1; }

if [[ -z ${SUDO_USER:-} || $SUDO_USER == root ]]; then
    echo "SUDO_USER is not set — run this as 'sudo $0' from your normal user," >&2
    echo "not from a root shell. AUR packages cannot be built as root." >&2
    exit 1
fi

command -v pacman >/dev/null || { echo "pacman not found — this is not Arch" >&2; exit 1; }

# ─── who this is being installed for ────────────────────────────────────────
# Asked here, before anything is installed, because the config carries absolute
# paths from the machine it was written on (/home/ivanc/…) and they are
# rewritten to this user's home further down.
# --yes means unattended, so it has to cover this prompt too — otherwise the one
# question asked before any step still blocks a scripted run that has a tty.
if [[ -z $USER_NAME ]]; then
    if [[ -t 0 ]] && (( ! ASSUME_YES )); then
        read -rp "install for which user? [$SUDO_USER] " USER_NAME
    fi
    USER_NAME=${USER_NAME:-$SUDO_USER}
fi

[[ $USER_NAME != root ]] || { echo "refusing to install for root" >&2; exit 1; }
# getent exits 2 for an unknown user and `set -o pipefail` would take that as
# the value of the whole substitution, killing the script without a word.
USER_HOME=$({ getent passwd "$USER_NAME" || true; } | cut -d: -f6)
[[ -n $USER_HOME ]] || { echo "no such user: $USER_NAME" >&2; exit 1; }
[[ -d $USER_HOME ]] || { echo "home directory for $USER_NAME not found" >&2; exit 1; }

# "yes for all" — asked once, before anything happens, so the whole install can
# be waved through without answering a dozen prompts. --yes presets it.
if (( ! ASSUME_YES )) && [[ -t 0 ]]; then
    read -rp "answer yes to every step from here on? [y/N] " _yesall
    case ${_yesall,,} in
        y|yes) ASSUME_YES=1; echo "  -> yes for all; --skip-* flags still apply" ;;
        *)     echo "  -> each step will ask" ;;
    esac
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
[[ -f $REPO_ROOT/config.kdl ]] || { echo "config.kdl not found in $REPO_ROOT" >&2; exit 1; }

step()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info()  { printf '    %s\n' "$*"; }
warn()  { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
as_user() { sudo -u "$USER_NAME" HOME="$USER_HOME" "$@"; }

# Announce a step and ask whether to run it. Returns 0 to proceed.
#
#   step_ask "Official packages" || { info "skipped"; ...; }
#
# Non-interactive runs must never hang here: this script runs under sudo and a
# `read` with no tty returns immediately with an empty reply, which would read
# as "no" and silently install nothing. So no tty means yes, same as --yes.
step_ask() {
    local title=$1 reply
    step "$title"
    if (( ASSUME_YES )); then return 0; fi
    if [[ ! -t 0 ]]; then return 0; fi
    read -rp "    run this step? [Y/n] " reply
    case ${reply,,} in
        n|no) return 1 ;;
        *)    return 0 ;;
    esac
}

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

# What actually happened, for the summary at the end. Steps can be declined one
# by one, so the summary has to report the result rather than restate the plan —
# it used to claim the config was linked and the shell changed even when both
# had been skipped.
DID_LINK_CONFIG=0
DID_CHANGE_SHELL=0

echo "user:   $USER_NAME ($USER_HOME)"
echo "config: $REPO_ROOT"
echo "greeter: $([[ $SKIP_GREETER == 1 ]] && echo "skipped" || echo "$GREETER")"

# yay builds as this user and calls sudo itself to install what it built. That
# is password-less only for the user who ran this script.
if [[ $USER_NAME != "$SUDO_USER" ]]; then
    warn "installing for $USER_NAME but sudo was run by $SUDO_USER —"
    warn "the AUR step will ask for $USER_NAME's password"
fi

# ─── hardware: microcode and GPU userspace ──────────────────────────────────
# This config was written on a Ryzen 7 5800U with integrated Radeon Vega, and
# the driver packages used to be hardcoded for it — an Intel or NVIDIA machine
# got AMD microcode it cannot use and no Vulkan driver for the GPU it has, which
# leaves niri with nothing but a software renderer. So the two vendor-specific
# things are detected here instead. --cpu / --gpu override the result.
#
# Detection reads sysfs directly rather than calling lspci: pciutils is not part
# of `base`, and the header above promises this script needs no more than base.

detect_cpu_vendor() {
    case $({ grep -m1 '^vendor_id' /proc/cpuinfo || true; } | cut -d: -f2 | tr -d ' \t') in
        AuthenticAMD) echo amd ;;
        GenuineIntel) echo intel ;;
        *)            echo none ;;
    esac
}

# Every display controller on the PCI bus, deduplicated to a vendor list. Class
# is matched on the 0x03 prefix, not on 0x030000: a laptop dGPU in an Optimus
# pair reports 0x030200 ("3D controller"), and matching only VGA would miss the
# discrete card on exactly the hybrid machines this is for.
detect_gpu_vendors() {
    local dev class vendor found=() v
    for dev in /sys/bus/pci/devices/*/; do
        [[ -r $dev/class && -r $dev/vendor ]] || continue
        class=$(<"$dev/class")
        [[ $class == 0x03* ]] || continue
        vendor=$(<"$dev/vendor")
        case $vendor in
            0x1002) v=amd ;;            # AMD/ATI
            0x8086) v=intel ;;
            0x10de) v=nvidia ;;
            # Everything else is a virtual or management adapter (VMware 0x15ad,
            # QEMU 0x1234, virtio 0x1af4, Cirrus 0x1013, ASPEED BMC 0x1a03).
            # Those run on mesa's software path and need no vendor driver.
            *) continue ;;
        esac
        [[ " ${found[*]-} " == *" $v "* ]] || found+=("$v")
    done
    # Unconditionally, and never a non-zero status: a machine with no GPU this
    # knows about is a normal outcome (a VM), not a failure, and returning 1
    # under `set -e` would kill the script there.
    echo "${found[*]-}"
}

step "Hardware"
[[ -n $CPU_VENDOR ]] || CPU_VENDOR=$(detect_cpu_vendor)
if [[ -n $GPU_VENDORS ]]; then
    read -ra GPU_LIST <<<"${GPU_VENDORS//,/ }"
else
    read -ra GPU_LIST <<<"$(detect_gpu_vendors)"
fi

# The microcode package is referenced again by the GRUB step below, which is
# what actually makes it load, so keep the name rather than only the vendor.
UCODE_PKG=""
case $CPU_VENDOR in
    amd)   UCODE_PKG=amd-ucode ;;
    intel) UCODE_PKG=intel-ucode ;;
esac

# Microcode is NOT part of `base`. Without it the CPU runs on the errata that
# shipped in its silicon.
HW_PKGS=()
if [[ -n $UCODE_PKG ]]; then
    info "CPU: $CPU_VENDOR -> $UCODE_PKG"
    HW_PKGS+=("$UCODE_PKG")
else
    warn "unknown CPU vendor — no microcode package; pass --cpu amd|intel to force one"
fi

# A base install has no GPU userspace at all. mesa is unconditional (it carries
# the OpenGL drivers for all three vendors and the software fallback); the
# Vulkan driver is per-vendor, and niri needs one to render on the GPU.
#
# NVIDIA is deliberately absent here — it is a DKMS kernel module, not just
# userspace, and gets its own step further down.
WANT_NVIDIA=0
for _v in ${GPU_LIST[@]+"${GPU_LIST[@]}"}; do
    case $_v in
        amd)    info "GPU: AMD -> vulkan-radeon";   HW_PKGS+=(vulkan-radeon) ;;
        intel)  info "GPU: Intel -> vulkan-intel";  HW_PKGS+=(vulkan-intel) ;;
        nvidia) info "GPU: NVIDIA -> asked about separately below"; WANT_NVIDIA=1 ;;
        none)   ;;
    esac
done
if (( ! ${#HW_PKGS[@]} )) || [[ " ${HW_PKGS[*]} " != *vulkan-* ]]; then
    if (( ! WANT_NVIDIA )); then
        warn "no AMD/Intel/NVIDIA GPU found — mesa's software renderer only"
        warn "on a VM that is expected; on real hardware pass --gpu amd|intel|nvidia"
    fi
fi

# ─── packages from the official repos ───────────────────────────────────────
PKGS=(
    # ── drivers / firmware ──────────────────────────────────────────────────
    # Microcode and the Vulkan driver, both chosen by the step above.
    ${HW_PKGS[@]+"${HW_PKGS[@]}"}
    mesa
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
    # (imagemagick also resizes the wallpaper in bin/noctalia-telegram-theme)
    imagemagick brightnessctl ffmpeg wlr-randr python libqalculate
    # bin/random-wallpaper is a GTK4 app (no libadwaita — it ships its own
    # theme); it talks to both wallpaper APIs with stdlib urllib.
    python-gobject gtk4 librsvg
    # apps. Dolphin is the file manager (Super+E in 70-binds.kdl); ark, okular
    # and imv are what it hands archives, documents and images to. The
    # associations are in share/mimeapps.list, copied into place further down.
    #
    # nautilus is deliberately NOT listed and equally deliberately not removed:
    # it is a hard dependency of xdg-desktop-portal-gnome above, which is the
    # only portal backend serving ScreenCast under niri (niri implements
    # org.gnome.Mutter.ScreenCast and that backend is what translates portal
    # calls into it — see the niri README). Removing it costs screen sharing.
    # So it stays on disk and is kept from ever being chosen, in both places
    # that can choose it: [Removed Associations] in share/mimeapps.list, and
    # the FileManager1 D-Bus override in share/dbus-1/services/.
    telegram-desktop dolphin ark okular imv
    # Runtime libraries for Zen, which is installed from the upstream tarball
    # (install/zen-install.sh) rather than from a package, so nothing pulls
    # these in on its own. Same list zen-browser-bin declares as its depends:
    # ffmpeg is already above, and ttf-font is covered by the noto fonts.
    gtk3 libxt dbus-glib nss mailcap
    # unarchiver provides `unar`, which sniffs the codepage of legacy archive
    # entry names. Ark's libzip backend follows the spec and reads unflagged
    # names as CP437, so a Windows-made ZIP with CP866 names extracts as
    # mojibake; bin/unar-here and the service menu above are the way around it.
    unarchiver
    # Qt theming, so Qt apps follow the session instead of falling back to their
    # own default styling. QT_QPA_PLATFORMTHEME "kde" in 40-environment.kdl
    # needs plasma-integration; kde-cli-tools backs the file dialogs and the
    # "Open With" window under that platform theme. kvantum is the style engine
    # iNiR ships a config for; the active style is Darkly, from the AUR, below.
    plasma-integration kde-cli-tools kvantum
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
    # Networking. The header calls this part of the assumed base system, and on
    # an install done through the guided installer it is — but `pacstrap base`
    # does not pull it in, and the Services step below then fails to enable a
    # unit that was never installed.
    networkmanager
)

if step_ask "Official packages (${#PKGS[@]} from the repos)"; then
    # Not fatal on its own: a dead mirror or one dropped package name used to
    # abort the whole script here with nothing but pacman's own error, no TODO
    # and no summary. The steps below degrade honestly instead.
    if ! pacman -Syu --needed --noconfirm "${PKGS[@]}"; then
        warn "pacman failed — bad mirror, no network, or a renamed package"
        warn "continuing; the steps below will work with whatever did install"
        TODO+=("re-run the package install: pacman -Syu --needed ${PKGS[*]}")
    fi

    # Microcode only takes effect once it is referenced from the boot entry.
    # grub-mkconfig finds either vendor's image on its own, so the only
    # vendor-specific thing here is what the messages name.
    if [[ -z $UCODE_PKG ]]; then
        :
    elif command -v grub-mkconfig >/dev/null && [[ -d /boot/grub ]]; then
        step "Regenerating GRUB config (picks up $UCODE_PKG)"
        if ! grub-mkconfig -o /boot/grub/grub.cfg; then
            warn "grub-mkconfig failed — the boot config was left as it was"
            TODO+=("regenerate the boot config: grub-mkconfig -o /boot/grub/grub.cfg")
        fi
    else
        warn "GRUB not found — microcode will not load until your bootloader references it"
        TODO+=("add the $UCODE_PKG initrd to your boot entry")
    fi
else
    warn "skipped — niri, kitty, fish and the rest are NOT installed"
    warn "the steps below assume these packages; expect them to fall short"
    TODO+=("install the base packages: pacman -S --needed ${PKGS[*]}")
fi

# ─── NVIDIA ─────────────────────────────────────────────────────────────────
# Its own step, and one that always asks even under --yes-for-all, because it is
# the only driver here that is a kernel module rather than userspace, and the
# only one that can leave the machine without a working session:
#
#   - nvidia-open-dkms supports Turing (RTX 20xx) and newer ONLY. On Maxwell or
#     Pascal it builds happily and then does not drive the card; those need
#     nvidia-dkms, which this script will not choose for you.
#   - DKMS needs linux-headers matching the running kernel. The header of this
#     script assumes them, but a base install that skipped them would produce a
#     module that never builds.
#
# egl-wayland is what lets Wayland compositors talk to the NVIDIA stack.
# nvidia_drm.modeset=1 is default-on in current packages, so the kernel cmdline
# is left alone.
if (( WANT_NVIDIA )); then
    step "NVIDIA GPU detected"
    info "nvidia-open-dkms + egl-wayland — Turing (RTX 20xx) and newer only"
    info "older cards (Maxwell/Pascal) need nvidia-dkms instead"

    NVIDIA_OK=0
    if [[ -t 0 ]]; then
        read -rp "    install nvidia-open-dkms? [y/N] " _nv
        case ${_nv,,} in y|yes) NVIDIA_OK=1 ;; esac
    else
        warn "not interactive — not installing an NVIDIA driver unasked"
    fi

    if (( NVIDIA_OK )); then
        if ! pacman -Qq linux-headers >/dev/null 2>&1; then
            warn "linux-headers is not installed — DKMS cannot build the module"
            info "installing it along with the driver"
        fi
        if pacman -S --needed --noconfirm linux-headers nvidia-open-dkms egl-wayland; then
            info "installed — if the card is pre-Turing, swap in nvidia-dkms"
        else
            warn "the NVIDIA driver failed to install"
            TODO+=("install the NVIDIA driver: pacman -S linux-headers nvidia-open-dkms egl-wayland")
        fi
    else
        warn "skipped — niri will fall back to software rendering on this GPU"
        TODO+=("install an NVIDIA driver: pacman -S linux-headers nvidia-open-dkms egl-wayland (Turing+) or nvidia-dkms (older)")
    fi
fi

# ─── AUR ────────────────────────────────────────────────────────────────────
AUR_PKGS=(
    darkly-bin          # Qt style — QT_STYLE_OVERRIDE in 40-environment.kdl
    noctalia-git        # the shell (v5, native C++ — does NOT need quickshell)
    # zen is deliberately NOT here — it comes from the upstream tarball, in its
    # own step below. See install/zen-install.sh for why.
    google-chrome
    yandex-music
    happ-desktop-bin
)

if [[ $SKIP_AUR == 1 ]]; then
    warn "AUR skipped — noctalia, chrome, yandex-music and happ NOT installed"
    TODO+=("install AUR packages later: yay -S ${AUR_PKGS[*]}")
elif ! step_ask "AUR packages (${AUR_PKGS[*]})"; then
    warn "skipped — noctalia, chrome, yandex-music and happ NOT installed"
    TODO+=("install AUR packages later: yay -S ${AUR_PKGS[*]}")
else
    step "AUR helper (yay)"
    # NOTE: `command` is a shell builtin, so `sudo -u user command -v yay` always
    # fails. Check as root instead — /usr/bin is on root's PATH too.
    HAVE_YAY=0
    if command -v yay >/dev/null 2>&1; then
        info "yay already present"
        HAVE_YAY=1
    else
        # Every step here reaches the network, and none of it is worth aborting
        # the whole install over: aur.archlinux.org and the sources makepkg
        # fetches go down far more often than the Arch mirrors do, and this runs
        # right after the package step has already succeeded. Failing here used
        # to kill the run at the worst possible point — most of the work done,
        # no summary, no TODO list.
        BUILD_DIR=$(as_user mktemp -d)
        if ! as_user git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$BUILD_DIR/yay-bin"; then
            warn "could not clone yay-bin from the AUR"
        # Build as the user (makepkg refuses to run as root), then install as
        # root ourselves. Using `makepkg -si` would make makepkg call `sudo
        # pacman` from inside a sudo session, which can block on a password
        # prompt if the timestamp expires during a long build.
        elif ! ( cd "$BUILD_DIR/yay-bin" && as_user makepkg -s --noconfirm ); then
            warn "yay-bin failed to build"
        elif ! pacman -U --noconfirm "$BUILD_DIR"/yay-bin/yay-bin-*.pkg.tar.*; then
            warn "could not install the yay-bin package"
        else
            HAVE_YAY=1
        fi
        rm -rf "$BUILD_DIR"
    fi

    if (( ! HAVE_YAY )); then
        warn "no AUR helper — noctalia, chrome, yandex-music and happ NOT installed"
        TODO+=("install yay, then: yay -S ${AUR_PKGS[*]}")
    else
        step "AUR packages"
        info "${AUR_PKGS[*]}"
        # --sudoloop keeps the sudo timestamp alive across long builds.
        as_user yay -S --needed --noconfirm --sudoloop "${AUR_PKGS[@]}" || {
            warn "one or more AUR packages failed to build"
            TODO+=("re-run: yay -S ${AUR_PKGS[*]}")
        }
    fi
fi

# ─── Zen ────────────────────────────────────────────────────────────────────
# Its own step, outside the AUR block on purpose: Zen no longer comes from the
# AUR, so --skip-aur must not skip it. The whole reason it is a tarball install
# is that zen-browser-bin ships an enterprise policy which disables the updater
# and puts a "managed by your organization" banner in Settings — see the header
# of install/zen-install.sh.
if step_ask "Zen Browser (upstream tarball -> /opt/zen)"; then
    # Runs as root, like the rest of this script, and is told which user ends up
    # owning /opt/zen — Zen's own updater writes into its install directory.
    if ! bash "$SCRIPT_DIR/zen-install.sh" --user "$USER_NAME"; then
        warn "Zen was not installed"
        TODO+=("install Zen: sudo $SCRIPT_DIR/zen-install.sh --user $USER_NAME")
    fi
else
    warn "skipped — Zen NOT installed; Super+W and the http/https defaults have"
    warn "nothing to open"
    TODO+=("install Zen: sudo $SCRIPT_DIR/zen-install.sh --user $USER_NAME")
fi

# ─── shell ──────────────────────────────────────────────────────────────────
CURRENT_SHELL=$(getent passwd "$USER_NAME" | cut -d: -f7)
if [[ $CURRENT_SHELL == /usr/bin/fish ]]; then
    step "Login shell"
    info "already fish"
    DID_CHANGE_SHELL=1
elif step_ask "Login shell ($CURRENT_SHELL -> fish)"; then
    # chsh fails if fish is not installed, which is exactly what happens after a
    # partial package step — and an unguarded failure here would abort the run
    # one step after it promised to carry on.
    if [[ ! -x /usr/bin/fish ]]; then
        warn "/usr/bin/fish not installed — leaving the shell as $CURRENT_SHELL"
        TODO+=("install fish, then: chsh -s /usr/bin/fish $USER_NAME")
    elif chsh -s /usr/bin/fish "$USER_NAME"; then
        DID_CHANGE_SHELL=1
        info "$CURRENT_SHELL -> /usr/bin/fish"
    else
        warn "chsh failed — shell left as $CURRENT_SHELL"
        TODO+=("chsh -s /usr/bin/fish $USER_NAME")
    fi
else
    info "left as $CURRENT_SHELL"
    TODO+=("dots/fish is installed but unused until: chsh -s /usr/bin/fish $USER_NAME")
fi

# ─── wallpapers ─────────────────────────────────────────────────────────────
# A step of its own, and deliberately not tied to anything else: the image set
# is ~83 MB and lives in a separate repository, so a clone of the config does
# not pay for it. bin/random-wallpaper is installed with the other helper
# scripts and is independent of this step — it downloads its own images.
#
# Runs before the config block because the noctalia settings seeded there name a
# wallpaper by absolute path and fall back to noctalia's own if the file is
# missing. Fetch first, or that fallback fires every time.
if [[ $SKIP_WALLPAPERS == 1 ]]; then
    step "Wallpapers"
    info "skipped (--skip-wallpapers)"
elif step_ask "Wallpapers (~83 MB from niri-wallpapers)"; then
    as_user mkdir -p "$USER_HOME/Pictures/Wallpapers"
    WALL_SRC=""
    if [[ -d $REPO_ROOT/wallpapers ]]; then
        # Present already — the machine this repo was written on, or someone
        # dropped the images in by hand. Use them rather than going to network.
        WALL_SRC="$REPO_ROOT/wallpapers"
        info "using the local wallpapers/ directory"
    else
        TMP_WALL=$(as_user mktemp -d)
        # https rather than ssh: this runs on machines with no key yet, same
        # reason the LVim clone below uses it. --depth 1 because the history of
        # an image set is worth nothing to an installer.
        if as_user git clone --quiet --depth 1 "$WALLPAPER_REPO" "$TMP_WALL/repo"; then
            # Strip the repository's own files so only images get copied.
            as_user rm -rf "$TMP_WALL/repo/.git" "$TMP_WALL/repo/README.md"
            WALL_SRC="$TMP_WALL/repo"
        else
            warn "could not clone $WALLPAPER_REPO — no network, or it is not public"
            TODO+=("wallpapers: git clone --depth 1 $WALLPAPER_REPO, copy the images into ~/Pictures/Wallpapers")
        fi
    fi

    if [[ -n $WALL_SRC ]]; then
        # -n so a re-run never clobbers wallpapers added since the last install.
        as_user cp -rn "$WALL_SRC"/. "$USER_HOME/Pictures/Wallpapers/"
        info "$(find "$WALL_SRC" -type f | wc -l) wallpaper(s) -> ~/Pictures/Wallpapers"
    fi
    # Not `[[ … ]] && rm`: under `set -e` a false test there is the last command
    # of the branch and would exit the script.
    if [[ -n ${TMP_WALL:-} ]]; then rm -rf "$TMP_WALL"; fi
else
    info "skipped — noctalia falls back to the wallpaper it ships"
fi

# ─── config ─────────────────────────────────────────────────────────────────
if [[ $SKIP_LINK == 1 ]]; then
    warn "config linking skipped"
else
    if step_ask "niri config"; then
        DID_LINK_CONFIG=1
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

        for s in lock-and-suspend niri-toggle-gaps wlsunset-restart \
                 claude-state noctalia-telegram-theme \
                 unar-here fix-legacy-names filemanager1-dispatch; do
            as_user ln -sf "$REPO_ROOT/bin/$s" "$USER_HOME/.local/bin/$s"
        done
        info "helper scripts linked into ~/.local/bin"

        # random-wallpaper goes system-wide instead. It is the one helper with a
        # .desktop entry, and a desktop entry is launched by whatever PATH the
        # launcher happens to have — which is not the shell's. /usr/bin is on
        # every PATH there is, so the entry can name an absolute path that does
        # not depend on $HOME either.
        #
        # A symlink rather than a copy, to match the rest of bin/: edits to the
        # repo are live, with no reinstall step. It does mean /usr/bin holds a
        # root-owned link into $USER_HOME, so it dangles if the repo moves —
        # rerunning this step fixes that.
        ln -sfn "$REPO_ROOT/bin/random-wallpaper" /usr/bin/random-wallpaper
        info "/usr/bin/random-wallpaper -> $REPO_ROOT/bin/random-wallpaper"

        # Dolphin right-click actions. These are what unar-here and
        # fix-legacy-names are reached through, so they follow the scripts.
        SERVICEMENU_DIR="$USER_HOME/.local/share/kio/servicemenus"
        as_user mkdir -p "$SERVICEMENU_DIR"
        for d in "$REPO_ROOT"/share/kio/servicemenus/*.desktop; do
            as_user ln -sf "$d" "$SERVICEMENU_DIR/$(basename "$d")"
        done
        info "Dolphin service menus linked into ~/.local/share/kio/servicemenus"

        # org.freedesktop.FileManager1 follows mimeapps.list. nautilus ships a
        # .service claiming that name too and cannot be uninstalled (see the
        # package list); ~/.local/share beats /usr/share, and what this one
        # activates is bin/filemanager1-dispatch rather than a fixed app.
        as_user mkdir -p "$USER_HOME/.local/share/dbus-1/services"
        as_user ln -sf "$REPO_ROOT/share/dbus-1/services/org.freedesktop.FileManager1.service" \
                "$USER_HOME/.local/share/dbus-1/services/org.freedesktop.FileManager1.service"
        info "FileManager1 D-Bus name pinned to Dolphin"

        # Default applications. Copied rather than linked: Dolphin and every
        # other app rewrites this file whenever you tick "set as default", and a
        # symlink would leave the repo permanently dirty. Its [Removed
        # Associations] section is what keeps nautilus from ever being offered.
        if [[ -f "$USER_HOME/.config/mimeapps.list" ]]; then
            info "mimeapps.list already present — left alone"
            TODO+=("compare ~/.config/mimeapps.list with share/mimeapps.list")
        else
            as_user cp "$REPO_ROOT/share/mimeapps.list" "$USER_HOME/.config/mimeapps.list"
            info "mimeapps.list copied"
        fi

        # XDG_MENU_PREFIX again, for D-Bus/systemd-activated services (kded6,
        # kiod6, xdg-desktop-portal-kde). 40-environment.kdl covers what niri
        # spawns and dots/fish covers terminals, but neither reaches these — and
        # any one of them rebuilding ksycoca without the prefix empties the
        # application index. See config.d/40-environment.kdl for what that costs.
        as_user mkdir -p "$USER_HOME/.config/environment.d"
        as_user ln -sf "$REPO_ROOT/share/environment.d/10-xdg-menu-prefix.conf" \
                "$USER_HOME/.config/environment.d/10-xdg-menu-prefix.conf"
        info "environment.d drop-in linked into ~/.config/environment.d"

        # Desktop entries, so the shell launcher can find random-wallpaper and
        # Zen. zen-install.sh links the same zen.desktop into /usr/share as
        # well, for the case where only that script is run; the user-level copy
        # wins, and both point at this file.
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
        # any absolute paths for the user chosen at the start. dots/ is included:
        # noctalia's settings.toml points at wallpapers by absolute path, Happ's
        # routing.json at an asset directory, and gp8.fish at a wine prefix.
        #
        # Only the path is rewritten, never the bare name. `dev.ivanc.RandomWallpaper`
        # is a reverse-DNS application id, matched by the window rule in
        # 90-user-extra.kdl and by the icon file name — renaming it would break both
        # and buys nothing.
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

        # Per-machine overrides. config.kdl includes this unconditionally and a
        # missing include is a hard parse error, so the empty copy has to exist
        # before anything validates the config.
        if [[ -f $REPO_ROOT/config.d/99-local.kdl ]]; then
            info "99-local.kdl already present — left alone"
        else
            as_user cp "$REPO_ROOT/config.d/99-local.kdl.example" \
                       "$REPO_ROOT/config.d/99-local.kdl"
            info "99-local.kdl created from the example (gitignored)"
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
    else
        warn "~/.config/niri not linked — niri will start on its own defaults"
        TODO+=("link the config: ln -s $REPO_ROOT ~/.config/niri (and bin/ into ~/.local/bin)")
    fi

    if step_ask "fish config"; then
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
    else
        warn "fish keeps its default config; the prompt and abbreviations are not installed"
        TODO+=("link the shell config: ln -s $REPO_ROOT/dots/fish ~/.config/fish")
    fi

    if step_ask "kitty config"; then
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
        # No TODO here: dots/noctalia/settings.toml enables the kitty template, so
        # colours follow the wallpaper from first login.
    else
        warn "kitty keeps its defaults — no palette, no padding, no font settings"
        TODO+=("link kitty.conf: ln -s $REPO_ROOT/dots/kitty/kitty.conf ~/.config/kitty/kitty.conf")
    fi

    if step_ask "telegram palette template"; then
        # The template noctalia-telegram-theme renders. It is config, not generated
        # output, so the directory is symlinked into the repo like kitty.conf is;
        # the script writes its rendered copy to a temp dir, never here.
        TG_TEMPLATE_DIR="$USER_HOME/.config/noctalia/telegram"
        as_user mkdir -p "$USER_HOME/.config/noctalia"
        if [[ -e $TG_TEMPLATE_DIR && ! -L $TG_TEMPLATE_DIR ]]; then
            as_user mv "$TG_TEMPLATE_DIR" "$TG_TEMPLATE_DIR.bak.$(date +%Y%m%d%H%M%S)"
        fi
        as_user ln -sfn "$REPO_ROOT/dots/telegram" "$TG_TEMPLATE_DIR"
        info "$TG_TEMPLATE_DIR -> $REPO_ROOT/dots/telegram"
        # The theme file itself cannot be applied from outside Telegram.
        TODO+=("Telegram: Settings -> Chat Settings -> Themes -> ... -> Open theme file, pick ~/.config/telegram-desktop/themes/noctalia.tdesktop-theme")
    else
        warn "Telegram will not follow the wallpaper — the palette template is not linked"
        TODO+=("link the template: ln -s $REPO_ROOT/dots/telegram ~/.config/noctalia/telegram")
    fi

    if step_ask "neovim (LVim)"; then
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
    else
        warn "~/.config/nvim left alone — nvim starts unconfigured"
        TODO+=("clone https://github.com/ivanovichelovek/LVim.git into ~/.config/nvim")
    fi

    if step_ask "app configs"; then
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

        # Those settings name a wallpaper by absolute path, and that file is
        # there only if the wallpapers step above actually ran — it can be
        # skipped by --skip-wallpapers, declined at its prompt, or fail to reach
        # the branch. In any of those cases point the settings at the wallpaper
        # noctalia ships and always installs, so the shell starts on something.
        # Runs on every install, not just the seeding one.
        SEEDED_WALL=$(grep -m1 -oE '^path = "[^"]+"' "$NOCTALIA_SETTINGS" 2>/dev/null | cut -d'"' -f2 || true)
        FALLBACK_WALL=/usr/share/noctalia/assets/noctalia-wallpaper.png
        if [[ -n ${SEEDED_WALL:-} && ! -f $SEEDED_WALL ]]; then
            if [[ -f $FALLBACK_WALL ]]; then
                as_user sed -i "s|$SEEDED_WALL|$FALLBACK_WALL|g" "$NOCTALIA_SETTINGS"
                warn "$(basename "$SEEDED_WALL") is missing — wallpaper reset to noctalia's default"
            else
                warn "wallpaper $SEEDED_WALL is missing and noctalia's default was not found"
                TODO+=("pick a wallpaper: noctalia msg wallpaper-set <path>")
            fi
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

        # Qt theming. Copied for the same reason as the two above: the apps
        # rewrite these files themselves. See dots/qt/README.md.
        for d in "$REPO_ROOT"/dots/qt/*rc; do
            [[ -f $d ]] || continue
            if [[ -f "$USER_HOME/.config/$(basename "$d")" ]]; then
                info "$(basename "$d") already present — left alone"
            else
                as_user cp "$d" "$USER_HOME/.config/"
                info "$(basename "$d") copied"
            fi
        done
        # Kvantum's own directory. Note the style actually in use is Darkly
        # (QT_STYLE_OVERRIDE); this only matters if you switch to Kvantum.
        if [[ -f "$USER_HOME/.config/Kvantum/kvantum.kvconfig" ]]; then
            info "kvantum.kvconfig already present — left alone"
        else
            as_user mkdir -p "$USER_HOME/.config/Kvantum"
            as_user cp "$REPO_ROOT/dots/qt/Kvantum/kvantum.kvconfig" \
                       "$USER_HOME/.config/Kvantum/"
            info "kvantum.kvconfig copied"
        fi
    else
        warn "noctalia and Happ start unconfigured; noctalia picks its own wallpaper"
        TODO+=("seed the app configs by re-running this step")
    fi

fi

# ─── greeter ────────────────────────────────────────────────────────────────
if [[ $SKIP_GREETER == 1 || $GREETER == none ]]; then
    warn "no display manager — log in on tty1 and run 'niri' by hand"
elif ! step_ask "Greeter ($GREETER)"; then
    warn "skipped — no display manager will be installed or enabled"
    info "log in on tty1 and run 'niri'; dots/fish/auto-Niri.fish does that for you"
    TODO+=("optional: re-run with --greeter $GREETER to set up a display manager")
else

    case $GREETER in
    regreet)
        # greetd itself is a tiny daemon (~1-2 MB resident); the greeter process
        # only lives until you log in. cage is the one-window compositor it runs in.
        # Guarded like every other network-facing command here: this is the last
        # step of the install, and a failure to fetch a greeter is no reason to
        # swallow the summary and the TODO list.
        if ! pacman -S --needed --noconfirm greetd greetd-regreet cage; then
            warn "could not install greetd/regreet/cage"
            TODO+=("install the greeter: pacman -S greetd greetd-regreet cage")
        fi
        # cage exits without this; see the PKGS comment above.
        if [[ ! -x /usr/bin/Xwayland ]]; then
            warn "/usr/bin/Xwayland missing — cage will crash-loop"
            pacman -S --needed --noconfirm xorg-xwayland || \
                TODO+=("install xorg-xwayland, or the greeter will crash-loop")
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
        if ! pacman -S --needed --noconfirm greetd greetd-tuigreet; then
            warn "could not install greetd/tuigreet"
            TODO+=("install the greeter: pacman -S greetd greetd-tuigreet")
        fi
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
        if ! pacman -S --needed --noconfirm greetd; then
            warn "could not install greetd"
            TODO+=("install the greeter: pacman -S greetd")
        fi
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
if step_ask "Services (NetworkManager, bluetooth)"; then
    # Never fatal. A missing unit here (packages step declined, or a base system
    # that ships something other than NetworkManager) used to kill the script on
    # its last step under `set -e`: the install had fully succeeded, and all the
    # user saw was an enable failure with the summary and TODO list never printed.
    for unit in NetworkManager.service bluetooth.service; do
        if systemctl enable "$unit" 2>/dev/null; then
            info "$unit enabled"
        else
            warn "could not enable $unit — not installed?"
            TODO+=("systemctl enable --now $unit")
        fi
    done
else
    warn "skipped — without NetworkManager there may be no network after reboot"
    TODO+=("systemctl enable --now NetworkManager.service bluetooth.service")
fi

as_user xdg-user-dirs-update || true

# ─── done ───────────────────────────────────────────────────────────────────
step "Done"

cat <<EOF

  Installed for: $USER_NAME
  niri config:   $( ((DID_LINK_CONFIG)) && echo "~/.config/niri -> $REPO_ROOT" || echo "NOT linked — step skipped")
  shell:         $( ((DID_CHANGE_SHELL)) && echo "fish" || echo "$CURRENT_SHELL — unchanged")
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
