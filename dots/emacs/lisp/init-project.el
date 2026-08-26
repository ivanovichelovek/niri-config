;;; init-project.el --- languages, LSP, treesitter, project nav -*- lexical-binding: t; -*-

;; Compiled grammars default to inside user-emacs-directory (~/.emacs.d/
;; tree-sitter/), which is going to be a symlink into the git repo — same
;; reasoning as the package-user-dir/eln-cache redirect in early-init.el.
;; Two separate variables, confirmed by reading treesit.el and
;; treesit-auto.el rather than assuming: treesit-extra-load-path is where
;; treesit *looks up* an already-installed grammar; where
;; treesit-install-language-grammar *writes* a new one is a completely
;; different default — (locate-user-emacs-file "tree-sitter") — unless
;; treesit--install-language-grammar-out-dir-history already has an entry,
;; which is the only hook available to redirect it (treesit-auto calls
;; treesit-install-language-grammar with no out-dir of its own). Both need
;; setting, or grammars keep landing back in ~/.emacs.d/tree-sitter.
(require 'treesit)
(defvar ic-treesit-dir (expand-file-name "tree-sitter" ic-cache-dir))
(setq treesit-extra-load-path (list ic-treesit-dir)
      treesit--install-language-grammar-out-dir-history (list ic-treesit-dir))

;; treesit-auto: installs and picks the right treesitter grammar per
;; buffer automatically, the same "just works" nvim-treesitter gives via
;; ensure_installed. Without it, Emacs 30's built-in treesit.el still
;; requires grammars to be compiled and registered by hand per language.
(use-package treesit-auto
  ;; `prompt' (the default) would block on y-or-n-p the first time any
  ;; treesit-covered mode opens with its grammar missing. `t' is the value
  ;; that actually means "just install it, no questions" — treesit-auto's
  ;; own install-all path specifically checks (eq treesit-auto-install t),
  ;; nothing else counts as quiet mode (confirmed: 'always silently did
  ;; nothing, neither installing nor prompting).
  :custom
  (treesit-auto-install t)
  ;; nvim's ensure_installed only listed typst explicitly (LazyVim's own
  ;; defaults cover the rest); restrict to the same rough set here rather
  ;; than treesit-auto-install-all's default of every grammar it knows —
  ;; that's 200+ languages, most of which will never be opened.
  (treesit-auto-langs '(typst c cpp python bash markdown yaml json))
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1)
  ;; Install every grammar treesit-auto knows about up front, the same
  ;; "just have it" experience nvim-treesitter's ensure_installed gave,
  ;; rather than depending on the lazy per-buffer install path.
  (treesit-auto-install-all))

;; eglot is built into Emacs 29+ and is the direct equivalent of
;; nvim-lspconfig here: thin LSP client, configured per server below rather
;; than through a plugin's opts table.
(use-package eglot
  :ensure nil
  :demand t                            ; eglot-server-programs must exist
                                        ; before typst-ts-mode/tex-mode below
                                        ; add entries to it at load time
  :hook ((c-ts-mode c++-ts-mode python-ts-mode) . eglot-ensure)
  :config
  ;; tinymist and texlab are launched from init-project's typst/tex setup
  ;; below (eglot-ensure is hooked from typst-ts-mode / tex modes there,
  ;; not from this list, since those aren't treesit-auto managed).
  (add-to-list 'eglot-server-programs '(c-ts-mode . ("clangd")))
  (add-to-list 'eglot-server-programs '(c++-ts-mode . ("clangd"))))

;; typst.lua's LSP half: tinymist for completion/hover/go-to-def. The
;; formatter (typstyle) is wired the same way nvim's conform.nvim was told
;; to prefer LSP formatting — eglot-format already prefers the server's
;; formatter when it offers one, no extra config needed.
(use-package typst-ts-mode
  :mode "\\.typ\\'"
  :hook (typst-ts-mode . eglot-ensure)
  :init
  (add-to-list 'eglot-server-programs
               '(typst-ts-mode . ("tinymist"))))

;; LaTeX: texlab as the LSP, tectonic as the compiler (see init-preview.el
;; for the build/watch commands — tectonic.lua's <leader>re/rw/rs).
(use-package tex-mode
  :ensure nil
  :hook (tex-mode . eglot-ensure)
  :init
  (add-to-list 'eglot-server-programs '(tex-mode . ("texlab"))))

(use-package markdown-mode
  :mode "\\.md\\'")

;; project.el ships with Emacs; nothing to install. dired's vim bindings
;; come from evil-collection (init-evil.el), same as every other built-in
;; mode it covers.
(setq project-vc-extra-root-markers '("typst.toml" "Tectonic.toml"))

(provide 'init-project)
;;; init-project.el ends here
