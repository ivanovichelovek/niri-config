;;; init-help.el --- getting-to-know-Emacs helpers -*- lexical-binding: t; -*-

;; org-hide-emphasis-markers is nil by default, so =C-w s= in a table cell
;; shows as the literal four characters =C-w s= instead of styled "C-w s"
;; with the = = hidden — the raw-markup look TUTORIAL.org's tables had.
;; org-appear is the standard fix for the obvious follow-up problem: with
;; markers hidden outright, there'd be no way to tell where they are to
;; edit around them — it shows them again only when point is on/inside the
;; markup, hidden everywhere else.
(use-package org
  :ensure nil
  :custom
  (org-hide-emphasis-markers t)
  (org-pretty-entities t))

(use-package org-appear
  :hook (org-mode . org-appear-mode))

;; evil-tutor: vimtutor adapted for evil. Not about this config specifically
;; (that's TUTORIAL.org) — about the handful of places evil's emulation is
;; thinner than actual vim (registers, marks, the jumplist), for someone who
;; already knows vim cold and doesn't need hjkl explained.
(use-package evil-tutor
  :commands evil-tutor-start)

(defun ic-open-tutorial ()
  "Open this config's own hands-on walkthrough (SPC h t)."
  (interactive)
  (find-file (expand-file-name "TUTORIAL.org" user-emacs-directory)))

(with-eval-after-load 'general
  (ic/leader
    "h" '(:ignore t :which-key "  help")
    "h t" '(ic-open-tutorial :which-key " this config's tutorial")
    "h e" '(evil-tutor-start :which-key " evil-tutor (vimtutor)")
    "h k" '(describe-key :which-key " describe key")
    "h f" '(describe-function :which-key " describe function")
    "h v" '(describe-variable :which-key " describe variable")))

(provide 'init-help)
;;; init-help.el ends here
