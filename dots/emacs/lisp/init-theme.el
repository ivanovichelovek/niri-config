;;; init-theme.el --- wallpaper-derived colours -*- lexical-binding: t; -*-

;; base16.lua's job, minus the SIGUSR1 half.
;;
;; noctalia's "neovim" template regenerates lua/matugen.lua from the current
;; Material You palette on every wallpaper change and signals nvim over
;; SIGUSR1. There's no "emacs" template, and no signal to catch even if
;; there were — but matugen.lua is a plain file on disk with the sixteen
;; base16 hex codes noctalia already computed, and it gets rewritten
;; (not appended) on every change. Watching that file with filenotify and
;; reparsing it gets the same live-reload with no changes to noctalia's
;; side, and it survives an Emacs restart or daemon the way a one-shot
;; signal handler wouldn't.
;;
;; If nvim's config ever moves or gets uninstalled, this just stops
;; reloading — reapply with `ic-theme-apply' by hand, or point
;; `ic-theme-source-file' at wherever the palette lives instead.

(require 'color)
(require 'filenotify)

(defvar ic-theme-source-file
  (expand-file-name "~/.config/nvim/lua/matugen.lua")
  "Where noctalia's matugen template writes the current base16 palette.")

(defvar ic-theme--colors nil
  "Alist of (base00 . \"#rrggbb\") ... base0F, from the last parse.")

(defun ic-theme--parse (file)
  "Pull base00..base0F hex codes out of noctalia's generated matugen.lua."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (let (colors)
        (dolist (slot '("base00" "base01" "base02" "base03" "base04" "base05"
                         "base06" "base07" "base08" "base09" "base0A" "base0B"
                         "base0C" "base0D" "base0E" "base0F"))
          (goto-char (point-min))
          (when (re-search-forward
                 (format "%s *= *['\"]\\(#[0-9a-fA-F]\\{6\\}\\)['\"]" slot)
                 nil t)
            (push (cons (intern slot) (match-string 1)) colors)))
        (nreverse colors)))))

(defun ic-theme--get (slot)
  (alist-get slot ic-theme--colors))

;; HSL midpoint, not the nvim side's Oklch — Emacs's built-in color.el only
;; gives HSL/CIE-Lab, and for a two-color blend used purely to keep
;; punctuation a shade off from body text, the perceptual difference isn't
;; worth pulling in a dependency-free Oklch implementation for.
(defun ic-theme--punctuation-color ()
  (let ((dim (ic-theme--get 'base04))
        (text (ic-theme--get 'base05))
        (tertiary (ic-theme--get 'base09)))
    (when (and dim text tertiary)
      (let* ((hsl-dim (apply #'color-rgb-to-hsl (color-name-to-rgb dim)))
             (hsl-text (apply #'color-rgb-to-hsl (color-name-to-rgb text)))
             (hsl-tert (apply #'color-rgb-to-hsl (color-name-to-rgb tertiary)))
             (l (/ (+ (nth 2 hsl-dim) (nth 2 hsl-text)) 2.0)))
        (apply #'color-rgb-to-hex
               (append (color-hsl-to-rgb (nth 0 hsl-tert) (nth 1 hsl-tert) l) '(2)))))))

(defun ic-theme-apply ()
  "(Re)build the `noctalia' custom theme from the current palette and load it."
  (interactive)
  (setq ic-theme--colors (ic-theme--parse ic-theme-source-file))
  (if (null ic-theme--colors)
      (message "ic-theme: %s not readable, skipping" ic-theme-source-file)
    (ic-theme--apply-colors)))

(defun ic-theme--apply-colors ()
  (let ((b00 (ic-theme--get 'base00)) (b01 (ic-theme--get 'base01))
        (b02 (ic-theme--get 'base02)) (b03 (ic-theme--get 'base03))
        (b04 (ic-theme--get 'base04)) (b05 (ic-theme--get 'base05))
        (b07 (ic-theme--get 'base07)) (b08 (ic-theme--get 'base08))
        (b09 (ic-theme--get 'base09)) (b0a (ic-theme--get 'base0A))
        (b0b (ic-theme--get 'base0B)) (b0c (ic-theme--get 'base0C))
        (b0d (ic-theme--get 'base0D)) (b0e (ic-theme--get 'base0E))
        (punct (ic-theme--punctuation-color))
        (specs nil))
    (setq specs
          (list
           `(default ((t (:foreground ,b05 :background ,b00))))
           `(cursor ((t (:background ,b05))))
           `(fringe ((t (:background ,b00))))
           `(region ((t (:background ,b02))))
           `(hl-line ((t (:background ,b01))))
           `(vertical-border ((t (:foreground ,b02))))
           `(line-number ((t (:foreground ,b03 :background ,b00))))
           `(line-number-current-line ((t (:foreground ,b05 :background ,b01))))
           `(mode-line ((t (:foreground ,b05 :background ,b01))))
           `(mode-line-inactive ((t (:foreground ,b03 :background ,b01))))
           `(minibuffer-prompt ((t (:foreground ,b08))))

           `(font-lock-comment-face ((t (:foreground ,b03))))
           `(font-lock-string-face ((t (:foreground ,b0b))))
           `(font-lock-keyword-face ((t (:foreground ,b0e))))
           `(font-lock-function-name-face ((t (:foreground ,b0d))))
           `(font-lock-variable-name-face ((t (:foreground ,b08))))
           `(font-lock-type-face ((t (:foreground ,b0a))))
           `(font-lock-constant-face ((t (:foreground ,b09))))
           `(font-lock-builtin-face ((t (:foreground ,b0c))))

           `(link ((t (:foreground ,b0d :underline t))))
           `(success ((t (:foreground ,b0b))))
           `(warning ((t (:foreground ,b0a))))
           `(error ((t (:foreground ,b08))))

           `(corfu-default ((t (:foreground ,b05 :background ,b01))))
           `(corfu-current ((t (:foreground ,b00 :background ,b0d))))
           `(vertico-current ((t (:background ,b02))))))
    ;; base16-nvim spends this slot on delimiters and it's practically
    ;; invisible against Material You's error_container red — see
    ;; ic-theme--punctuation-color. Only set it if this Emacs build knows
    ;; the face (treesit fontification, Emacs 29+).
    (when (and punct (facep 'font-lock-punctuation-face))
      (push `(font-lock-punctuation-face ((t (:foreground ,punct)))) specs))
    (apply #'custom-set-faces specs)
    (ignore b07)))

;; Transparent background — transparent.nvim's job. alpha-background is a
;; frame parameter, not a face, so it lives here rather than in the
;; custom-set-faces block above; unlike the nvim side there's no per-widget
;; "markview drew an opaque plaque over this" problem to work around, since
;; nothing here paints its own background independent of the theme faces.
(defvar ic-theme-alpha-background 92
  "0-100; matches transparent.nvim's effect closely enough at ~90-95.")

(defun ic-theme--apply-transparency (&optional frame)
  (set-frame-parameter (or frame (selected-frame))
                        'alpha-background ic-theme-alpha-background))

(add-hook 'after-make-frame-functions #'ic-theme--apply-transparency)
(add-to-list 'default-frame-alist (cons 'alpha-background ic-theme-alpha-background))

;; Live reload: same trigger nvim's base16.lua reacts to (noctalia rewrote
;; the palette file), just watched instead of signalled.
(defvar ic-theme--watch-descriptor nil)
(defvar ic-theme--reload-timer nil)

(defun ic-theme--on-file-change (_event)
  ;; Debounce: a rewrite is often a truncate + write, i.e. two events: fire
  ;; on the trailing edge of a 200ms quiet window rather than reparsing a
  ;; half-written file.
  (when ic-theme--reload-timer (cancel-timer ic-theme--reload-timer))
  (setq ic-theme--reload-timer
        (run-with-timer 0.2 nil #'ic-theme-apply)))

(defun ic-theme--start-watch ()
  (when (and (file-exists-p ic-theme-source-file)
             (not ic-theme--watch-descriptor))
    (setq ic-theme--watch-descriptor
          (file-notify-add-watch ic-theme-source-file '(change)
                                  #'ic-theme--on-file-change))))

(ic-theme-apply)
(ic-theme--start-watch)

(provide 'init-theme)
;;; init-theme.el ends here
