;;; init-preview.el --- build & live-preview PDF, in a split -*- lexical-binding: t; -*-

;; Merges what used to be three separate files (typst.lua, tectonic.lua,
;; markdown-pdf.lua) plus their shared preview_util.lua, because the thing
;; that made them separate files in nvim — each one shelling a build tool
;; out to an *external* zathura process, with all the pid-guarding and
;; focus-stealing workarounds that implies — doesn't apply here. The
;; preview is just a pdf-view buffer in a window; auto-revert-mode
;; (init-pdf.el) is what makes it "live", not this file.
;;
;; Keys, same letters as the nvim side, bound buffer-locally per major mode:
;;   SPC r e   build once and open
;;   SPC r w   watch / autobuild toggle (typst watch, or rebuild on save)
;;   SPC r s   stop watching

;; ---------------------------------------------------------------------
;; shared helpers (preview_util.lua)
;; ---------------------------------------------------------------------

(defun ic-preview-root (markers)
  "Nearest ancestor directory containing one of MARKERS, else the buffer's own."
  (or (seq-some (lambda (m) (locate-dominating-file default-directory m)) markers)
      default-directory))

(defun ic-preview-open (pdf)
  "Show PDF in a window on the right, without stealing focus from the
source buffer — the in-buffer equivalent of preview_util.lua's
zathura-without-a-second-instance dance."
  (let* ((buf (or (find-buffer-visiting pdf)
                   (find-file-noselect pdf)))
         (existing (get-buffer-window buf)))
    (unless existing
      (display-buffer buf '((display-buffer-in-side-window)
                             (side . right) (window-width . 0.5))))
    (with-current-buffer buf
      (when (and (buffer-modified-p) (not (verify-visited-file-modtime buf)))
        (revert-buffer :ignore-auto :noconfirm)))))

(defun ic-preview--run (name program args root callback)
  "Run PROGRAM ARGS in ROOT asynchronously; CALLBACK gets (success stderr-string)."
  (let* ((err-buf (generate-new-buffer (format " *%s-err*" name)))
         (default-directory root))
    (make-process
     :name name
     :command (cons program args)
     :stderr err-buf
     :sentinel
     (lambda (_proc event)
       (when (string-match-p "\\(finished\\|exited\\)" event)
         (let* ((ok (string-prefix-p "finished" event))
                (stderr (with-current-buffer err-buf (buffer-string))))
           (kill-buffer err-buf)
           (funcall callback ok stderr)))))))

;; ---------------------------------------------------------------------
;; typst (typst.lua)
;; ---------------------------------------------------------------------

(defvar ic-typst--watchers (make-hash-table :test 'equal)
  "src path -> running `typst watch' process.")

(defun ic-typst--pdf-for (src) (concat (file-name-sans-extension src) ".pdf"))

(defun ic-typst-build ()
  "Typst: compile once and open the PDF (<leader>re)."
  (interactive)
  (let* ((src (buffer-file-name))
         (out (ic-typst--pdf-for src))
         (root (ic-preview-root '("typst.toml" ".git"))))
    (message "typst: собираю…")
    (ic-preview--run
     "typst-build" "typst" (list "compile" "--root" root src out) root
     (lambda (ok stderr)
       (if ok (ic-preview-open out) (message "typst: %s" stderr))))))

(defun ic-typst-watch-stop (&optional quiet)
  "Typst: stop `typst watch' for this buffer (<leader>rs)."
  (interactive)
  (let* ((src (buffer-file-name))
         (proc (gethash src ic-typst--watchers)))
    (if (not proc)
        (unless quiet (message "typst: watch не запущен"))
      (delete-process proc)
      (remhash src ic-typst--watchers)
      (unless quiet (message "typst: watch остановлен")))))

(defun ic-typst-watch-toggle ()
  "Typst: toggle live-preview via `typst watch' (<leader>rw)."
  (interactive)
  (let* ((src (buffer-file-name))
         (out (ic-typst--pdf-for src))
         (root (ic-preview-root '("typst.toml" ".git"))))
    (if (gethash src ic-typst--watchers)
        (ic-typst-watch-stop)
      (let* ((default-directory root)
             (proc (make-process
                    :name "typst-watch"
                    :command (list "typst" "watch" "--root" root src out)
                    :filter
                    (lambda (_proc chunk)
                      (when (string-match-p "error:" chunk)
                        (message "typst watch: %s" chunk)))
                    :sentinel
                    (lambda (_proc _event) (remhash src ic-typst--watchers)))))
        (puthash src proc ic-typst--watchers)
        ;; The first PDF doesn't exist yet when the process starts — poll
        ;; briefly for it, same 200ms/25-try budget as typst.lua's timer.
        (let ((tries 0) (timer nil))
          (setq timer
                (run-with-timer
                 0.2 0.2
                 (lambda ()
                   (setq tries (1+ tries))
                   (cond
                    ((not (gethash src ic-typst--watchers))
                     (cancel-timer timer))
                    ((file-readable-p out)
                     (cancel-timer timer)
                     (ic-preview-open out)
                     (message "typst: watch запущен"))
                    ((> tries 25)
                     (cancel-timer timer)
                     (message "typst: PDF так и не появился")))))))))))

(with-eval-after-load 'typst-ts-mode
  (general-define-key :states 'normal :keymaps 'typst-ts-mode-map :prefix "SPC r"
    "e" #'ic-typst-build
    "w" #'ic-typst-watch-toggle
    "s" #'ic-typst-watch-stop))

;; Orphaned `typst watch' processes outliving Emacs are as useless here as
;; they were outliving nvim.
(add-hook 'kill-emacs-hook
          (lambda () (maphash (lambda (_src proc) (delete-process proc)) ic-typst--watchers)))

;; ---------------------------------------------------------------------
;; LaTeX via tectonic (tectonic.lua)
;; ---------------------------------------------------------------------

(defvar-local ic-tex--autobuild nil "Non-nil while rebuild-on-save is active for this buffer.")

(defun ic-tex--pdf-for (src) (concat (file-name-sans-extension src) ".pdf"))

(defun ic-tex--compile (src root callback)
  (ic-preview--run "tectonic" "tectonic" (list "--keep-logs" "--synctex" src) root callback))

(defun ic-tex-build ()
  "LaTeX: compile once via tectonic and open the PDF (<leader>re)."
  (interactive)
  (let* ((src (buffer-file-name))
         (root (ic-preview-root '("Tectonic.toml" ".latexmkrc" ".git"))))
    (message "tectonic: собираю…")
    (ic-tex--compile
     src root
     (lambda (ok stderr)
       (if ok (ic-preview-open (ic-tex--pdf-for src)) (message "tectonic: %s" stderr))))))

(defun ic-tex-autobuild-stop (&optional quiet)
  "LaTeX: turn off rebuild-on-save (<leader>rs)."
  (interactive)
  (if (not ic-tex--autobuild)
      (unless quiet (message "tectonic: пересборка по сохранению не включена"))
    (remove-hook 'after-save-hook #'ic-tex--autobuild-fn t)
    (setq ic-tex--autobuild nil)
    (unless quiet (message "tectonic: пересборка по сохранению выключена"))))

(defun ic-tex--autobuild-fn ()
  (let ((src (buffer-file-name))
        (root (ic-preview-root '("Tectonic.toml" ".latexmkrc" ".git"))))
    (ic-tex--compile
     src root
     (lambda (ok stderr)
       (if ok (ic-preview-open (ic-tex--pdf-for src)) (message "tectonic: %s" stderr))))))

(defun ic-tex-autobuild-toggle ()
  "LaTeX: toggle rebuild-on-save (<leader>rw)."
  (interactive)
  (if ic-tex--autobuild
      (ic-tex-autobuild-stop)
    (setq ic-tex--autobuild t)
    (add-hook 'after-save-hook #'ic-tex--autobuild-fn nil t)
    (message "tectonic: пересборка по сохранению включена")
    (ic-tex-build)))

(with-eval-after-load 'tex-mode
  (general-define-key :states 'normal :keymaps 'tex-mode-map :prefix "SPC r"
    "e" #'ic-tex-build
    "w" #'ic-tex-autobuild-toggle
    "s" #'ic-tex-autobuild-stop))

;; ---------------------------------------------------------------------
;; markdown -> pdf via pandoc + typst engine (markdown-pdf.lua)
;; ---------------------------------------------------------------------

(defun ic-md--pdf-path (src)
  ;; Generated output, not config — belongs in the cache dir (ic-cache-dir,
  ;; early-init.el), same reasoning as markdown-pdf.lua putting these under
  ;; stdpath("cache") rather than next to the source.
  (let ((dir (expand-file-name "md-pdf" ic-cache-dir)))
    (make-directory dir t)
    (expand-file-name (concat (file-name-base src) ".pdf") dir)))

(defun ic-md-build-view ()
  "Markdown: pandoc+typst -> PDF and open it (<leader>rm / <leader>re)."
  (interactive)
  (let* ((src (buffer-file-name))
         (out (ic-md--pdf-path src)))
    (message "markdown → pdf: собираю…")
    (ic-preview--run
     "md-pdf" "pandoc"
     (list src "-o" out "--pdf-engine=typst" "--toc"
           "-V" "margin-x=2cm" "-V" "margin-y=2cm"
           "-V" "mainfont=Adwaita Sans"
           "-V" "monofont=JetBrainsMono Nerd Font Mono")
     default-directory
     (lambda (ok stderr)
       (if ok (ic-preview-open out) (message "markdown → pdf: %s" stderr))))))

(with-eval-after-load 'markdown-mode
  (general-define-key :states 'normal :keymaps 'markdown-mode-map :prefix "SPC r"
    "e" #'ic-md-build-view
    "m" #'ic-md-build-view))

(provide 'init-preview)
;;; init-preview.el ends here
