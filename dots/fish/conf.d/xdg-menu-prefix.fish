# KDE/KIO application lookup depends on this.
#
# kbuildsycoca6 builds its application index by walking
# $XDG_MENU_PREFIX + "applications.menu". Arch's plasma-workspace ships only
# /etc/xdg/menus/plasma-applications.menu — there is no plain applications.menu.
# With the variable unset, kbuildsycoca6 finds no menu and indexes zero
# applications, which breaks every KIO app lookup (Dolphin's "Open With" is
# empty, double-clicking a file prompts instead of opening it).
#
# Niri exports this too (config.d/40-environment.kdl), but that does not reach
# TTY/SSH shells. Without it here, launching any KDE app from a terminal can
# trigger a sycoca rebuild with the prefix missing and wipe the index again.
set -gx XDG_MENU_PREFIX plasma-
