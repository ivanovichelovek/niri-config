;;; init-prog.el --- TODO highlighting, clang-format -*- lexical-binding: t; -*-

;; todo-comments.lua, ported keyword-for-keyword. Same rationale for the
;; explicit hex codes: they're deliberately NOT pulled from the generated
;; theme (init-theme.el) — the whole point in the nvim version was that a
;; low-contrast wallpaper palette must never make a TODO unreadable, so
;; these stay fixed regardless of what ic-theme-apply is doing.
(use-package hl-todo
  :hook (prog-mode . hl-todo-mode)
  :custom
  (hl-todo-keyword-faces
   '(("TODO"   . "#FBBA73")
     ("FIXME"  . "#FFB4AB") ("FIX" . "#FFB4AB") ("BUG" . "#FFB4AB")
     ("HACK"   . "#E0C1A3")
     ("WARN"   . "#E0C1A3") ("WARNING" . "#E0C1A3") ("XXX" . "#E0C1A3")
     ("PERF"   . "#FBBA73") ("OPTIMIZE" . "#FBBA73")
     ("NOTE"   . "#BECC9B") ("INFO" . "#BECC9B")
     ("TEST"   . "#BECC9B")))
  :general
  (:states 'normal
   "]t" #'hl-todo-next
   "[t" #'hl-todo-previous))

;; Format C/C++ with clang-format on save, using scripts/.clang-format —
;; searched upward from the file the same way find_clang_format() in
;; keymaps.lua/autocmds.lua did, falling back to the copy shipped with this
;; config (scripts/.clang-format here, mirroring nvim's
;; ~/.config/nvim/scripts/.clang-format).
(defun ic-find-clang-format (dir)
  (or (locate-dominating-file dir "scripts/.clang-format")
      nil))

(defun ic-clang-format-style-file ()
  (let ((found (ic-find-clang-format default-directory)))
    (if found
        (expand-file-name "scripts/.clang-format" found)
      (expand-file-name "scripts/.clang-format" user-emacs-directory))))

(defun ic-clang-format-buffer ()
  "Format the current C/C++ buffer with clang-format (<leader>rf)."
  (interactive)
  (let ((style (ic-clang-format-style-file)))
    (if (not (file-readable-p style))
        (message "clang-format: .clang-format не найден")
      (call-process "clang-format" nil nil nil
                    (concat "--style=file:" style) "-i" buffer-file-name)
      (revert-buffer :ignore-auto :noconfirm)
      (message "Formatted: %s" (file-name-nondirectory buffer-file-name)))))

(defun ic-clang-format-on-save ()
  (when (executable-find "clang-format")
    (ic-clang-format-buffer)))

(dolist (hook '(c-ts-mode-hook c++-ts-mode-hook c-mode-hook c++-mode-hook))
  (add-hook hook
            (lambda ()
              (add-hook 'after-save-hook #'ic-clang-format-on-save nil t)
              (with-eval-after-load 'general
                (general-define-key :states 'normal :keymaps 'local :prefix "SPC r"
                  "f" #'ic-clang-format-buffer)))))

(provide 'init-prog)
;;; init-prog.el ends here
