#!/usr/bin/env bash
#
# Install Zen Browser into /opt/zen from the official GitHub release tarball.
#
#   sudo ./install/zen-install.sh
#
# Why not the AUR package: zen-browser-bin ships its own
# /opt/zen-browser-bin/distribution/policies.json with DisableAppUpdate, because
# a pacman-managed directory must not rewrite itself behind pacman's back. Any
# enterprise policy at all makes Firefox — and so Zen — show "Your browser is
# being managed by your organization" in Settings, with the update section
# greyed out. The upstream tarball has no distribution/ directory, so neither
# banner nor the disabled updater appear.
#
# /opt/zen is chowned to the user for the same reason: Zen's built-in updater
# writes into its own install directory, exactly like on Windows and macOS. Root
# ownership would leave "Check for updates" failing on permissions instead.
#
# Re-running is cheap: the installed version is read from application.ini and
# the download is skipped when it already matches the latest release.
#
set -euo pipefail

REPO_URL="https://github.com/zen-browser/desktop"
TARBALL="zen.linux-x86_64.tar.xz"
DEST="/opt/zen"

USER_NAME=""
FORCE=0

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \?//'
    cat <<'EOF'

Options:
  --user <name>   install for this user (default: $SUDO_USER)
  -f, --force     reinstall even if /opt/zen is already the latest release
  -h, --help      this text
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --user)     USER_NAME=${2:?--user needs a value}; shift 2 ;;
        -f|--force) FORCE=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

step()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info()  { printf '    %s\n' "$*"; }
warn()  { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
die()   { printf '\033[1;31m  ! %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run this with sudo: sudo $0"

USER_NAME=${USER_NAME:-${SUDO_USER:-}}
[[ -n $USER_NAME && $USER_NAME != root ]] \
    || die "no target user — run as 'sudo $0' from your normal account, or pass --user"
# getent exits 2 for an unknown user, and `set -o pipefail` would make that the
# status of the whole substitution and kill the script without a word.
USER_ENT=$({ getent passwd "$USER_NAME" || true; })
[[ -n $USER_ENT ]] || die "no such user: $USER_NAME"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
DESKTOP_SRC="$REPO_ROOT/share/applications/zen.desktop"
[[ -f $DESKTOP_SRC ]] || die "$DESKTOP_SRC not found — is this the niri-config repo?"

# ─── which version is out, and which is installed ───────────────────────────
step "Latest release"
# The /releases/latest URL redirects to /releases/tag/<version>, which is the
# tag without needing the API (and without its unauthenticated rate limit).
LATEST_URL=$(curl -fsSL --retry 3 --max-time 60 -o /dev/null -w '%{url_effective}' \
             "$REPO_URL/releases/latest") \
    || die "could not reach GitHub — no network?"
LATEST=${LATEST_URL##*/}
# Not "latest": that is the URL unredirected, i.e. GitHub answered with
# something other than a release page.
[[ -n $LATEST && $LATEST != latest ]] || die "could not read a version out of $LATEST_URL"
info "$LATEST"

INSTALLED=""
if [[ -f $DEST/application.ini ]]; then
    INSTALLED=$(sed -n 's/^Version=//p' "$DEST/application.ini" | head -1)
    info "installed: ${INSTALLED:-unknown}"
fi

# The AUR package matters to this test as much as the version does: while it is
# installed its policies.json is still on disk, and a /opt/zen that is already
# current would otherwise let this script exit with the banner still there.
if [[ -n $INSTALLED && $INSTALLED == "$LATEST" && $FORCE -eq 0 ]] \
   && ! pacman -Qq zen-browser-bin >/dev/null 2>&1; then
    info "already up to date — nothing to do (use --force to reinstall)"
    exit 0
fi

# ─── download and unpack ────────────────────────────────────────────────────
# Upstream publishes no checksum or signature for this asset (only .zsync files,
# and only for the AppImages), so https plus the layout check below is all the
# verification there is to do.
step "Downloading $TARBALL"
# Under /opt, not the default /tmp: /tmp is tmpfs, so `mv` out of it would be a
# copy across filesystems — reopening the very half-written-/opt/zen window the
# staging directory exists to close — and would hold the ~400 MB extract in RAM
# on the way. On the same filesystem both moves below are renames.
TMP=$(mktemp -d -p /opt .zen-install.XXXXXX) || die "cannot write to /opt"
trap 'rm -rf "$TMP"' EXIT

curl -fSL --retry 3 --max-time 900 --progress-bar \
     -o "$TMP/$TARBALL" "$REPO_URL/releases/download/$LATEST/$TARBALL" \
    || die "download failed"

step "Unpacking"
tar -xf "$TMP/$TARBALL" -C "$TMP" || die "the archive is corrupt"
[[ -x $TMP/zen/zen && -f $TMP/zen/application.ini ]] \
    || die "unexpected archive layout — no zen/zen in $TARBALL"
# Belt and braces: upstream ships no distribution/ today, and if that ever
# changes this is the file that puts the banner back.
rm -f "$TMP/zen/distribution/policies.json"

# ─── the AUR package, if it is still there ──────────────────────────────────
# Deliberately after the download and not before it: removing the old browser
# first and then failing to fetch the new one would leave the machine with no
# browser at all. Still before the desktop entry is linked further down, though
# — pacman owns /usr/share/applications/zen.desktop and would take the symlink
# with it.
#
# Plain -R, not -Rns: recursive removal would pull gtk3 and ffmpeg out too.
MIGRATED=0
if pacman -Qq zen-browser-bin >/dev/null 2>&1; then
    step "Removing the AUR package (zen-browser-bin)"
    info "the profile in ~/.config/zen is a separate directory and is not touched"
    if pacman -R --noconfirm zen-browser-bin; then
        info "removed"
        MIGRATED=1
        # These went in as dependencies of zen-browser-bin, and the tarball
        # needs every one of them. Left marked as dependencies they are orphans
        # the moment the package goes, and the next `pacman -Qtdq | pacman -Rns -`
        # would quietly take Zen's runtime out from under it.
        # mailcap, not the mime-types that zen-browser-bin's depends list names:
        # that one is a virtual provide, and `pacman -D` only takes real package
        # names.
        pacman -D -q --asexplicit gtk3 libxt dbus-glib nss mailcap ffmpeg \
            >/dev/null 2>&1 || warn "could not mark Zen's runtime deps as explicit"
    else
        warn "could not remove zen-browser-bin — its policies.json will keep the"
        warn "\"managed by your organization\" banner alive; remove it by hand"
    fi
fi

step "Installing into $DEST"
if [[ -e $DEST ]]; then
    rm -rf "$DEST.old"
    mv "$DEST" "$DEST.old"
fi
mv "$TMP/zen" "$DEST"
chown -R "$USER_NAME:" "$DEST"
rm -rf "$DEST.old"
info "$(sed -n 's/^Version=//p' "$DEST/application.ini" | head -1), owned by $USER_NAME"

# ─── how the rest of the system reaches it ──────────────────────────────────
# Both names: config.d/70-binds.kdl spawns "zen-browser" on Super+W, while
# everything else calls it "zen". /usr/bin rather than /usr/local/bin for the
# reason spelled out at the random-wallpaper symlink in bootstrap.sh — a desktop
# entry or a compositor bind runs with whatever PATH the launcher has, not the
# shell's, and /usr/bin is on every PATH there is.
step "Symlinks and desktop entry"
ln -sfn "$DEST/zen" /usr/bin/zen
ln -sfn "$DEST/zen" /usr/bin/zen-browser
info "/usr/bin/zen, /usr/bin/zen-browser -> $DEST/zen"

# The name zen.desktop is load-bearing: share/mimeapps.list names it as the
# handler for http, https and text/html. Renaming it silently unsets the
# default browser.
ln -sfn "$DESKTOP_SRC" /usr/share/applications/zen.desktop
update-desktop-database /usr/share/applications 2>/dev/null || true
info "/usr/share/applications/zen.desktop -> $DESKTOP_SRC"

# The tarball carries the icon at five sizes but no hicolor layout, so the
# entry's Icon=zen resolves to nothing until they are copied out.
for size in 16 32 48 64 128; do
    src="$DEST/browser/chrome/icons/default/default$size.png"
    [[ -f $src ]] || continue
    dir="/usr/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$dir"
    cp -f "$src" "$dir/zen.png"
done
gtk-update-icon-cache -qtf /usr/share/icons/hicolor 2>/dev/null || true
info "icons installed into /usr/share/icons/hicolor"

step "Done"
info "Zen $LATEST is in $DEST and updates itself — Settings shows no policy banner"

# Only after a migration: on a fresh machine there is no old profile to lose.
#
# Firefox keys a profile to the *install path*. ~/.config/zen/installs.ini holds
# one [<hash-of-install-dir>] section per installation, and that is what decides
# which profile starts. /opt/zen-browser-bin and /opt/zen hash differently, so
# the first launch from here finds no section of its own and creates a brand new
# empty profile. Nothing is deleted — but it looks exactly as if everything were.
#
# Two things that sound like fixes and are not, both checked on a real profile
# rather than assumed:
#
#   - `zen -P "<name>"` opens the right profile but does NOT claim the install.
#     The named-profile path bypasses profile selection, so installs.ini gains
#     nothing and the next plain launch goes back to the empty one.
#   - Default=1 on the wanted [ProfileN] is ignored while that profile is still
#     claimed by the old install's section (Locked=1). Zen makes a new profile
#     anyway rather than adopting a claimed one.
#
# What does work is repointing the section, after the launch that creates it.
# This script cannot do it: the hash does not exist until Zen has run once, and
# root has no business editing a user's profile index anyway.
if (( MIGRATED )); then
    ZEN_CFG="$(getent passwd "$USER_NAME" | cut -d: -f6)/.config/zen"
    if [[ -f $ZEN_CFG/installs.ini ]]; then
        printf '\n'
        warn "the install path changed, so Zen will not recognise your profile on"
        warn "first launch and will start on a new empty one. Nothing was deleted."
        printf '\n'
        info "To reattach it — see 'Reattaching the profile' in the README:"
        info "  1. start Zen once and close it again"
        info "  2. in $ZEN_CFG/installs.ini a new [<hash>] section has appeared;"
        info "     point its Default= at your real profile, and do the same for the"
        info "     matching [Install<hash>] section in profiles.ini"
        info "  3. drop the section for the old install path and the [ProfileN]"
        info "     entry of the empty profile step 1 created"
        printf '\n'
        info "profiles currently listed, largest first:"
        du -sh "$ZEN_CFG"/*/ 2>/dev/null | sort -rh | sed 's/^/      /'
    fi
fi
