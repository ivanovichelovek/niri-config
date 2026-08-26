;;; early-init.el --- runs before init.el, before package.el, before the UI paints -*- lexical-binding: t; -*-

;; GC during startup only slows things down — package.el and 30-odd
;; use-package blocks run in one shot, not interactively. Raise the
;; threshold here, drop it back to something sane once init.el is done
;; (see the hook at the bottom of init.el).
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; Same idea for file-name-handler-alist: TRAMP/compressed-file hooks run on
;; every require during startup and buy nothing since nothing remote or
;; gzipped loads this early. Restored after startup too.
(defvar ic--file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil)

;; menu-bar/tool-bar/scroll-bar are disabled here rather than in init.el so
;; the frame never flashes them for a frame before they're turned off.
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars . nil) default-frame-alist)

;; This is a GUI-only config (pdf-tools rasterises PDF pages into real
;; images, which a -nw terminal frame cannot display), so there's no
;; terminal-frame code path to keep fast here.
(setq default-frame-alist
      (append '((width . 120) (height . 45)) default-frame-alist))

;; package.el is initialized by hand in init.el (after adding MELPA), so
;; skip the automatic init this early — it would run before the archive
;; list is even set.
(setq package-enable-at-startup nil)

;; This whole directory (user-emacs-directory) is going to be a symlink
;; into the niri-config git repo (dots/emacs) — same treatment as
;; ~/.config/fish. Downloaded packages, the compiled epdfinfo server and
;; native-comp's .eln cache do NOT belong in a git repo (easily gigabytes,
;; none of it hand-written), the way lazy.nvim's plugins live in
;; ~/.local/share/nvim rather than inside ~/.config/nvim. Both of these
;; must be set before package.el/native-comp touch them, hence early-init
;; rather than init.el.
(defvar ic-cache-dir (expand-file-name "emacs/" (or (getenv "XDG_CACHE_HOME") "~/.cache")))
(setq package-user-dir (expand-file-name "elpa" ic-cache-dir))
(when (fboundp 'startup-redirect-eln-cache)
  (startup-redirect-eln-cache (expand-file-name "eln-cache" ic-cache-dir)))

;; Native-comp warnings are noise for anything not authored here (every
;; third-party package trips a handful on first byte-compile).
(setq native-comp-async-report-warnings-errors 'silent)

(provide 'early-init)
;;; early-init.el ends here
