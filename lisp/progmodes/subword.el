;;; subword.el --- Handling capitalized subwords in a nomenclature

;; Copyright (C) 2004-2013 Free Software Foundation, Inc.

;; Author: Masatake YAMATO

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package was cc-submode.el before it was recognized being
;; useful in general and not tied to C and c-mode at all.

;; This package provides `subword' oriented commands and a minor mode
;; (`subword-mode') that substitutes the common word handling
;; functions with them.  It also provides the `superword-mode' minor
;; mode that treats symbols as words, the opposite of `subword-mode'.

;; In spite of GNU Coding Standards, it is popular to name a symbol by
;; mixing uppercase and lowercase letters, e.g. "GtkWidget",
;; "EmacsFrameClass", "NSGraphicsContext", etc.  Here we call these
;; mixed case symbols `nomenclatures'.  Also, each capitalized (or
;; completely uppercase) part of a nomenclature is called a `subword'.
;; Here are some examples:

;;  Nomenclature           Subwords
;;  ===========================================================
;;  GtkWindow          =>  "Gtk" and "Window"
;;  EmacsFrameClass    =>  "Emacs", "Frame" and "Class"
;;  NSGraphicsContext  =>  "NS", "Graphics" and "Context"

;; The subword oriented commands defined in this package recognize
;; subwords in a nomenclature to move between them and to edit them as
;; words.  You also get a mode to treat symbols as words instead,
;; called `superword-mode' (the opposite of `subword-mode').

;; In the minor mode, all common key bindings for word oriented
;; commands are overridden by the subword oriented commands:

;; Key     Word oriented command      Subword oriented command (also superword)
;; ============================================================
;; M-f     `forward-word'             `subword-forward'
;; M-b     `backward-word'            `subword-backward'
;; M-@     `mark-word'                `subword-mark'
;; M-d     `kill-word'                `subword-kill'
;; M-DEL   `backward-kill-word'       `subword-backward-kill'
;; M-t     `transpose-words'          `subword-transpose'
;; M-c     `capitalize-word'          `subword-capitalize'
;; M-u     `upcase-word'              `subword-upcase'
;; M-l     `downcase-word'            `subword-downcase'
;;
;; Note: If you have changed the key bindings for the word oriented
;; commands in your .emacs or a similar place, the keys you've changed
;; to are also used for the corresponding subword oriented commands.

;; To make the mode turn on automatically, put the following code in
;; your .emacs:
;;
;; (add-hook 'c-mode-common-hook 'subword-mode)
;;

;; To make the mode turn `superword-mode' on automatically for
;; only some modes, put the following code in your .emacs:
;;
;; (add-hook 'c-mode-common-hook 'superword-mode)
;;

;; Acknowledgment:
;; The regular expressions to detect subwords are mostly based on
;; the old `c-forward-into-nomenclature' originally contributed by
;; Terry_Glanfield dot Southern at rxuk dot xerox dot com.

;; TODO: ispell-word.

;;; Code:

(defvar subword-forward-function 'subword-forward-internal
  "Function to call for forward subword movement.")

(defvar subword-backward-function 'subword-backward-internal
  "Function to call for backward subword movement.")

(defconst subword-forward-regexp
  "\\W*\\(\\([[:upper:]]*\\(\\W\\)?\\)[[:lower:][:digit:]]*\\)"
  "Regexp used by `subword-forward-internal'.")

(defconst subword-backward-regexp
  "\\(\\(\\W\\|[[:lower:][:digit:]]\\)\\([[:upper:]]+\\W*\\)\\|\\W\\w+\\)"
  "Regexp used by `subword-backward-internal'.")

(defvar subword-mode-map
  (let ((map (make-sparse-keymap)))
    (dolist (cmd '(forward-word backward-word mark-word kill-word
				backward-kill-word transpose-words
                                capitalize-word upcase-word downcase-word
                                left-word right-word))
      (let ((othercmd (let ((name (symbol-name cmd)))
                        (string-match "\\([[:alpha:]-]+\\)-word[s]?" name)
                        (intern (concat "subword-" (match-string 1 name))))))
        (define-key map (vector 'remap cmd) othercmd)))
    map)
  "Keymap used in `subword-mode' minor mode.")

;;;###autoload
(define-minor-mode subword-mode
  "Toggle subword movement and editing (Subword mode).
With a prefix argument ARG, enable Subword mode if ARG is
positive, and disable it otherwise.  If called from Lisp, enable
the mode if ARG is omitted or nil.

Subword mode is a buffer-local minor mode.  Enabling it remaps
word-based editing commands to subword-based commands that handle
symbols with mixed uppercase and lowercase letters,
e.g. \"GtkWidget\", \"EmacsFrameClass\", \"NSGraphicsContext\".

Here we call these mixed case symbols `nomenclatures'.  Each
capitalized (or completely uppercase) part of a nomenclature is
called a `subword'.  Here are some examples:

  Nomenclature           Subwords
  ===========================================================
  GtkWindow          =>  \"Gtk\" and \"Window\"
  EmacsFrameClass    =>  \"Emacs\", \"Frame\" and \"Class\"
  NSGraphicsContext  =>  \"NS\", \"Graphics\" and \"Context\"

The subword oriented commands activated in this minor mode recognize
subwords in a nomenclature to move between subwords and to edit them
as words.

\\{subword-mode-map}"
    :lighter " ,"
    (when subword-mode (superword-mode -1)))

(define-obsolete-function-alias 'c-subword-mode 'subword-mode "23.2")

;;;###autoload
(define-global-minor-mode global-subword-mode subword-mode
  (lambda () (subword-mode 1))
  :group 'convenience)

(defun subword-forward (&optional arg)
  "Do the same as `forward-word' but on subwords.
See the command `subword-mode' for a description of subwords.
Optional argument ARG is the same as for `forward-word'."
  (interactive "^p")
  (unless arg (setq arg 1))
  (cond
   ((< 0 arg)
    (dotimes (i arg (point))
      (funcall subword-forward-function)))
   ((> 0 arg)
    (dotimes (i (- arg) (point))
      (funcall subword-backward-function)))
   (t
    (point))))

(put 'subword-forward 'CUA 'move)

(defun subword-backward (&optional arg)
  "Do the same as `backward-word' but on subwords.
See the command `subword-mode' for a description of subwords.
Optional argument ARG is the same as for `backward-word'."
  (interactive "^p")
  (subword-forward (- (or arg 1))))

(defun subword-right (&optional arg)
  "Do the same as `right-word' but on subwords."
  (interactive "^p")
  (if (eq (current-bidi-paragraph-direction) 'left-to-right)
      (subword-forward arg)
    (subword-backward arg)))

(defun subword-left (&optional arg)
  "Do the same as `left-word' but on subwords."
  (interactive "^p")
  (if (eq (current-bidi-paragraph-direction) 'left-to-right)
      (subword-backward arg)
    (subword-forward arg)))

(defun subword-mark (arg)
  "Do the same as `mark-word' but on subwords.
See the command `subword-mode' for a description of subwords.
Optional argument ARG is the same as for `mark-word'."
  ;; This code is almost copied from `mark-word' in GNU Emacs.
  (interactive "p")
  (cond ((and (eq last-command this-command) (mark t))
	 (set-mark
	  (save-excursion
	    (goto-char (mark))
	    (subword-forward arg)
	    (point))))
	(t
	 (push-mark
	  (save-excursion
	    (subword-forward arg)
	    (point))
	  nil t))))

(put 'subword-backward 'CUA 'move)

(defun subword-kill (arg)
  "Do the same as `kill-word' but on subwords.
See the command `subword-mode' for a description of subwords.
Optional argument ARG is the same as for `kill-word'."
  (interactive "p")
  (kill-region (point) (subword-forward arg)))

(defun subword-backward-kill (arg)
  "Do the same as `backward-kill-word' but on subwords.
See the command `subword-mode' for a description of subwords.
Optional argument ARG is the same as for `backward-kill-word'."
  (interactive "p")
  (subword-kill (- arg)))

(defun subword-transpose (arg)
  "Do the same as `transpose-words' but on subwords.
See the command `subword-mode' for a description of subwords.
Optional argument ARG is the same as for `transpose-words'."
  (interactive "*p")
  (transpose-subr 'subword-forward arg))

(defun subword-downcase (arg)
  "Do the same as `downcase-word' but on subwords.
See the command `subword-mode' for a description of subwords.
Optional argument ARG is the same as for `downcase-word'."
  (interactive "p")
  (let ((start (point)))
    (downcase-region (point) (subword-forward arg))
    (when (< arg 0)
      (goto-char start))))

(defun subword-upcase (arg)
  "Do the same as `upcase-word' but on subwords.
See the command `subword-mode' for a description of subwords.
Optional argument ARG is the same as for `upcase-word'."
  (interactive "p")
  (let ((start (point)))
    (upcase-region (point) (subword-forward arg))
    (when (< arg 0)
      (goto-char start))))

(defun subword-capitalize (arg)
  "Do the same as `capitalize-word' but on subwords.
See the command `subword-mode' for a description of subwords.
Optional argument ARG is the same as for `capitalize-word'."
  (interactive "p")
  (condition-case nil
      (let ((count (abs arg))
            (start (point))
            (advance (>= arg 0)))

        (dotimes (i count)
          (if advance
              (progn
                (re-search-forward "[[:alpha:]]")
                (goto-char (match-beginning 0)))
            (subword-backward))
          (let* ((p (point))
                 (pp (1+ p))
                 (np (subword-forward)))
            (upcase-region p pp)
            (downcase-region pp np)
            (goto-char (if advance np p))))
        (unless advance
          (goto-char start)))
    (search-failed nil)))



(defvar superword-mode-map subword-mode-map
  "Keymap used in `superword-mode' minor mode.")

;;;###autoload
(define-minor-mode superword-mode
  "Toggle superword movement and editing (Superword mode).
With a prefix argument ARG, enable Superword mode if ARG is
positive, and disable it otherwise.  If called from Lisp, enable
the mode if ARG is omitted or nil.

Superword mode is a buffer-local minor mode.  Enabling it remaps
word-based editing commands to superword-based commands that
treat symbols as words, e.g. \"this_is_a_symbol\".

The superword oriented commands activated in this minor mode
recognize symbols as superwords to move between superwords and to
edit them as words.

\\{superword-mode-map}"
    :lighter " ²"
    (when superword-mode (subword-mode -1)))

;;;###autoload
(define-global-minor-mode global-superword-mode superword-mode
  (lambda () (superword-mode 1))
  :group 'convenience)


;;
;; Internal functions
;;
(defun subword-forward-internal ()
  (if superword-mode
      (forward-symbol 1)
    (if (and
         (save-excursion
           (let ((case-fold-search nil))
             (re-search-forward subword-forward-regexp nil t)))
         (> (match-end 0) (point)))
        (goto-char
         (cond
          ((and (< 1 (- (match-end 2) (match-beginning 2)))
                ;; If we have an all-caps word with no following lower-case or
                ;; non-word letter, don't leave the last char (bug#13758).
                (not (and (null (match-beginning 3))
                          (eq (match-end 2) (match-end 1)))))
           (1- (match-end 2)))
          (t
           (match-end 0))))
      (forward-word 1))))

(defun subword-backward-internal ()
  (if superword-mode
      (forward-symbol -1)
    (if (save-excursion
          (let ((case-fold-search nil))
            (re-search-backward subword-backward-regexp nil t)))
        (goto-char
         (cond
          ((and (match-end 3)
                (< 1 (- (match-end 3) (match-beginning 3)))
                (not (eq (point) (match-end 3))))
           (1- (match-end 3)))
          (t
           (1+ (match-beginning 0)))))
      (backward-word 1))))



(provide 'subword)
(provide 'superword)

;;; subword.el ends here
