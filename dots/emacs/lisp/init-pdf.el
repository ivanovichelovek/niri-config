;;; init-pdf.el --- honest PDF, in the buffer -*- lexical-binding: t; -*-

;; This is the entire reason for the migration: pdf-tools renders through
;; poppler straight into the buffer — text selection, search, links,
;; continuous scroll, SyncTeX — instead of the kitty-graphics-protocol
;; screenshot nvim was stuck with (see pdf-buffer.lua's pdftotext fallback
;; and preview_util.lua's external-zathura dance, both now unnecessary).
;; The epdfinfo server MELPA ships pdf-tools with a pre-generated
;; server/configure that references config.guess/config.sub/install-sh/
;; ar-lib/compile/missing — none of which are in the tarball. autobuild
;; only runs `autoreconf' when configure is *absent*, so the stale one
;; makes ./configure fail outright ("cannot find required auxiliary
;; files"). Removing it once forces autobuild down the autoreconf path,
;; which regenerates all of them correctly (verified on this machine:
;; autoconf/automake/libtool were already installed, only the generated
;; files were missing).
(defun ic-pdf-tools--fix-stale-configure ()
  (dolist (dir (file-expand-wildcards
                (expand-file-name "pdf-tools-*/server" package-user-dir)))
    (let ((configure (expand-file-name "configure" dir)))
      (when (and (file-exists-p configure)
                 (not (file-exists-p (expand-file-name "config.guess" dir))))
        (delete-file configure)))))

(use-package pdf-tools
  :magic ("%PDF" . pdf-view-mode)
  :config
  (ic-pdf-tools--fix-stale-configure)
  (pdf-tools-install :no-query)
  (setq-default pdf-view-display-size 'fit-width)
  ;; auto-revert-mode is what turns "rebuild on save" into a live preview:
  ;; typst/tectonic watch (init-preview.el) rewrites the PDF on disk, this
  ;; buffer notices and redraws, no zathura process or refocus dance needed.
  (add-hook 'pdf-view-mode-hook #'auto-revert-mode))

;; disable-mouse (init-core.el) only shadows mouse bindings through a
;; low-priority global minor-mode map, so pdf-view-mode-map's own
;; mouse-driven text selection and link-follow still win — worth knowing if
;; the touchpad-click guard ever feels inconsistent between buffers.

(provide 'init-pdf)
;;; init-pdf.el ends here
