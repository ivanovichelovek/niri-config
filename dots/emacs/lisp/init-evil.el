;;; init-evil.el --- vim emulation + leader key -*- lexical-binding: t; -*-

;; evil-collection is the piece that actually delivers on "vim navigation
;; everywhere", which the terminal side of this whole project (Zed, in
;; particular) could not: it rebinds vim-style keys across dired, magit,
;; help, ibuffer, compilation and dozens of other built-in modes, not just
;; the text-editing buffers evil itself covers.
(use-package evil
  :init
  (setq evil-want-integration t
        evil-want-keybinding nil     ; evil-collection wants to own this
        evil-want-C-u-scroll t
        evil-want-fine-undo t
        evil-undo-system 'undo-redo
        evil-respect-visual-line-mode t)
  :config
  (evil-mode 1))

(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

(use-package evil-surround
  :after evil
  :config
  (global-evil-surround-mode 1))

;; gcc / gc<motion> to comment-toggle, the evil-idiomatic binding for
;; newcomment.el (no separate ts-comments.nvim equivalent needed — Emacs's
;; own comment-dwim already knows every major mode's comment syntax).
(use-package evil-commentary
  :after evil
  :config
  (evil-commentary-mode 1))

;; general.el's job here is the same one LazyVim's <leader> table does:
;; namespaced, discoverable bindings under SPC, independent of which-key
;; needing them predeclared. which-key itself is built into Emacs 30 (the
;; real justbur/which-key, not a reimplementation — /usr/share/emacs/30.2/
;; lisp/which-key.el), so the popup in the screenshot needs no extra
;; package, just turning it on. Its defaults already match: bottom
;; side-window, sorted by key. The one default worth changing is the
;; 1-second idle delay, which reads as "did SPC do anything?" — LazyVim's
;; is 200ms.
(use-package general
  :after evil
  :config
  (setq which-key-idle-delay 0.4)
  (which-key-mode 1)

  (general-create-definer ic/leader
    :states '(normal visual motion)
    :keymaps 'override
    :prefix "SPC")

  ;; Icons are plain characters from the Nerd Font already in use for the
  ;; terminal/kitty (JetBrainsMono Nerd Font Mono) — which-key just prints
  ;; whatever string you give it, there's no icon system to configure.
  (ic/leader
    "f" '(:ignore t :which-key "  file")
    "f f" '(find-file :which-key " find file")
    "f r" '(recentf-open :which-key " recent files")
    "f s" '(save-buffer :which-key " save")

    "b" '(:ignore t :which-key "  buffer")
    "b b" '(consult-buffer :which-key " switch buffer")
    "b d" '(kill-current-buffer :which-key " kill buffer")
    "b n" '(next-buffer :which-key " next buffer")
    "b p" '(previous-buffer :which-key " previous buffer")

    "p" '(:ignore t :which-key "  project")
    "p p" '(project-switch-project :which-key " switch project")
    "p f" '(project-find-file :which-key " find file in project")

    "r" '(:ignore t :which-key "  build/preview")

    "/" '(consult-ripgrep :which-key " grep")
    "e" '(dired-jump :which-key " file explorer")

    ;; Same letters as LazyVim's <leader>-/<leader>| — window splitting
    ;; itself is full vim already via evil's built-in C-w map (s/v/h/j/k/l/
    ;; o/c/w, no config needed), these are just leader-key aliases for the
    ;; two most common actions.
    "-" '(evil-window-split :which-key " split below")
    "|" '(evil-window-vsplit :which-key " split right")

    "w" '(:ignore t :which-key "  window")
    "w d" '(evil-window-delete :which-key " close window")
    "w o" '(delete-other-windows :which-key " only this window"))

  ;; ]b / [b — bracket-motion buffer cycling, same family as hl-todo's
  ;; ]t/[t (init-prog.el). Vanilla evil has no buffer-cycling bracket
  ;; motion of its own; next-buffer/previous-buffer are the built-in
  ;; Emacs commands SPC b n/p above also call.
  (general-define-key :states 'normal
    "]b" #'next-buffer
    "[b" #'previous-buffer))

(provide 'init-evil)
;;; init-evil.el ends here
