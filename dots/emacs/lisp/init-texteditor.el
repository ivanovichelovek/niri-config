;;; init-texteditor.el --- texteditor project commands -*- lexical-binding: t; -*-

;; Port of the :EdTest / :EdCov / :EdAsan user commands from keymaps.lua.
;; `compile' takes the place of nvim's `split | terminal <cmd>' — same
;; effect (a window with the build output, errors jump to source with
;; `next-error'/`C-x `'), without needing a terminal emulator package.

(defvar ic-texteditor-root "/home/ivanc/GitHub/my-config/texteditor")

(defun ic-texteditor--compile (cmd)
  (let ((default-directory ic-texteditor-root))
    (compile cmd)))

(defun ic-texteditor-test ()
  "Build and run texteditor's test suite (:EdTest)."
  (interactive)
  (let ((build (expand-file-name "build" ic-texteditor-root)))
    (ic-texteditor--compile
     (format "cmake -S %s -B %s -DCMAKE_CXX_COMPILER=clang++ && cmake --build %s --target tests -j$(nproc) && %s/tests"
             ic-texteditor-root build build build))))

(defun ic-texteditor-coverage ()
  "Build texteditor tests with coverage and print the report (:EdCov)."
  (interactive)
  (ic-texteditor--compile
   (expand-file-name "scripts/coverage.sh" ic-texteditor-root)))

(defun ic-texteditor-asan ()
  "Build and run texteditor's tests under AddressSanitizer (:EdAsan)."
  (interactive)
  (let ((build (expand-file-name "build-asan" ic-texteditor-root)))
    (ic-texteditor--compile
     (format "cmake -S %s -B %s -DCMAKE_CXX_COMPILER=clang++ -DASAN=ON && cmake --build %s --target tests -j$(nproc) && %s/tests"
             ic-texteditor-root build build build))))

(provide 'init-texteditor)
;;; init-texteditor.el ends here
