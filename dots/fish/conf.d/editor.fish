# Zed as the editor for git commit, crontab -e, sudoedit and the like.
# --wait keeps the caller blocked until the tab is closed, otherwise git
# sees the file unchanged and aborts the commit. EDITOR stays unset so
# anything that only honours EDITOR keeps its terminal fallback.
set -gx VISUAL "zeditor --wait"
