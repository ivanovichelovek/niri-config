;;; init-completion.el --- minibuffer + in-buffer completion -*- lexical-binding: t; -*-

;; Telescope's job (fuzzy-find files/buffers/grep results in a minibuffer-ish
;; UI) is split here across vertico (the UI), orderless (the fuzzy matching)
;; and consult (the actual find-file/buffer/grep commands) — three small
;; packages instead of one big one, but that's the standard Emacs split, not
;; a corner cut for this migration.
(use-package vertico
  :config (vertico-mode 1))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

(use-package marginalia
  :config (marginalia-mode 1))

(use-package consult)

(use-package embark
  :bind (("C-." . embark-act)))

(use-package embark-consult
  :after (embark consult))

;; corfu is nvim-cmp/blink.cmp's counterpart: a small completion-at-point
;; popup, fed by whatever backend is active (eglot's LSP completion, plain
;; dabbrev, etc.) rather than owning completion logic itself.
(use-package corfu
  :init (global-corfu-mode 1)
  :custom
  (corfu-auto t)
  (corfu-auto-delay 0.15)
  (corfu-auto-prefix 2)
  (corfu-cycle t))

(use-package cape
  :init
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-dabbrev))

(provide 'init-completion)
;;; init-completion.el ends here
