;;; init-core.el --- baseline options -*- lexical-binding: t; -*-

;; Analogous to lua/config/options.lua: things that are always set, not tied
;; to a specific package.

(setq inhibit-startup-screen t
      initial-scratch-message nil
      ring-bell-function 'ignore
      use-short-answers t)           ; y/n instead of yes/no

(set-language-environment "UTF-8")
(set-default-coding-systems 'utf-8)

(setq-default indent-tabs-mode nil
              tab-width 4
              fill-column 100)

;; Backups/autosaves/locks: no-littering (init.el) already redirects
;; backup-directory-alist and auto-save-file-name-transforms into
;; ic-cache-dir, out from underfoot of every project directory. Just the
;; lockfiles left to turn off.
(setq create-lockfiles nil)

;; File added/changed on disk (typst/tectonic watch rewriting a PDF,
;; clang-format rewriting a source file, git checkout) should just show up —
;; this is what makes the pdf-tools live-preview in init-preview.el work at
;; all, same role auto-revert plays for zathura in the old nvim setup.
(setq auto-revert-verbose nil
      auto-revert-avoid-polling t)
(global-auto-revert-mode 1)

(recentf-mode 1)
(save-place-mode 1)
(savehist-mode 1)

;; fish as the interactive shell (M-x shell), same as vim.o.shell = "fish".
;; shell-file-name is left on the system default (dash/bash) on purpose:
;; `compile' and `shell-command' shell out with POSIX `sh -c "..."' syntax
;; internally, which fish does not speak — only the interactive M-x shell
;; buffer should run fish.
(setq explicit-shell-file-name "/usr/bin/fish"
      explicit-fish-args '("-i"))

;; No mouse inside the editor: a stray touchpad click must not move point.
;; Mirrors vim.opt.mouse = "" — the pointer itself still works (niri keeps
;; its own click-to-focus, and text selection for copy still drags fine
;; since that's handled by the terminal/compositor, not this).
(use-package disable-mouse
  :config
  (global-disable-mouse-mode))

;; Folding: no treesitter-fold equivalent to nvim-ufo is wired up here
;; (hideshow is enough for "fold a block", and evil already binds
;; zR/zM/zr/zm/za/zo/zc to it once hs-minor-mode is on — no per-language
;; config needed the way nvim-ufo required a provider table).
(add-hook 'prog-mode-hook #'hs-minor-mode)

;; column/line numbers, matches LazyVim defaults
(setq column-number-mode t)
(global-display-line-numbers-mode 1)
(setq display-line-numbers-type 'relative)

(provide 'init-core)
;;; init-core.el ends here
