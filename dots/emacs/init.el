;;; init.el --- entry point -*- lexical-binding: t; -*-

;; Analogous to lua/config/lazy.lua: bootstrap the package manager, then hand
;; off to one file per concern under lisp/ (mirrors the one-file-per-plugin
;; layout under nvim's lua/plugins/).

(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/"))
      ;; GNU/NonGNU ship fewer, more vetted packages — prefer them over a
      ;; MELPA package of the same name when both exist.
      package-archive-priorities
      '(("gnu" . 3) ("nongnu" . 2) ("melpa" . 1)))
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

;; use-package is built into Emacs 30; :ensure t by default so every block
;; below both declares and installs its package, same as a lazy.nvim spec.
(require 'use-package)
(setq use-package-always-ensure t
      use-package-verbose nil)

;; no-littering picks up where early-init.el's package-user-dir/eln-cache
;; redirect left off: it points recentf/savehist/save-place/backups/
;; bookmarks/eshell/url/tramp and everything else that defaults to writing
;; inside user-emacs-directory at ic-cache-dir instead, so the only things
;; left under ~/.emacs.d (the git-tracked symlink target) are the files in
;; this repo. Must load before any package below that would otherwise
;; create its own file there first (recentf in init-core.el, in particular).
(use-package no-littering
  :init
  (setq no-littering-etc-directory (expand-file-name "etc/" ic-cache-dir)
        no-littering-var-directory (expand-file-name "var/" ic-cache-dir))
  :config
  (setq custom-file (no-littering-expand-etc-file-name "custom.el")))

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; Load order matters: evil before anything that binds keys via
;; evil-collection or general.el, theme before things that read its faces
;; (hl-todo's fallback colours aside), pdf before preview (preview opens PDF
;; buffers).
(require 'init-core)
(require 'init-evil)
(require 'init-completion)
(require 'init-project)
(require 'init-theme)
(require 'init-pdf)
(require 'init-preview)
(require 'init-prog)
(require 'init-texteditor)
(require 'init-help)

;; Undo the early-init.el GC/file-handler relaxation now that startup's done,
;; but land on a threshold well above the 800kb default — still generous for
;; interactive use, just not "never collect".
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 32 1024 1024)
                  gc-cons-percentage 0.1
                  file-name-handler-alist ic--file-name-handler-alist)))

(provide 'init)
;;; init.el ends here
