;;; isearch-x.el --- extended isearch handling commands

;; Copyright (C) 1995 Electrotechnical Laboratory, JAPAN.
;; Licensed to the Free Software Foundation.
;; Copyright (C) 2001 Free Software Foundation, Inc.

;; Keywords: multilingual, isearch

;; Author: Kenichi HANDA <handa@etl.go.jp>
;; Maintainer: Kenichi HANDA <handa@etl.go.jp>

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;;; Code:

;;;###autoload
(defun isearch-toggle-specified-input-method ()
  "Select an input method and turn it on in interactive search."
  (interactive)
  (let ((overriding-terminal-local-map nil))
    (toggle-input-method t))
  (setq isearch-input-method-function input-method-function
	isearch-input-method-local-p t)
  (setq input-method-function nil)
  (isearch-update))

;;;###autoload
(defun isearch-toggle-input-method ()
  "Toggle input method in interactive search."
  (interactive)
  (let ((overriding-terminal-local-map nil))
    (toggle-input-method))
  (setq isearch-input-method-function input-method-function
	isearch-input-method-local-p t)
  (setq input-method-function nil)
  (isearch-update))

(defvar isearch-minibuffer-local-map
  (let ((map (copy-keymap minibuffer-local-map)))
    (define-key map [with-keyboard-coding] 'isearch-with-keyboard-coding)
    (define-key map [with-input-method] 'isearch-with-input-method)
    map)
  "Keymap to use in minibuffer for multibyte character inputting in isearch.")

;; Exit from recursive edit safely.  Set in `after-change-functions'
;; by isearch-with-keyboard-coding.
(defun isearch-exit-recursive-edit (start end length)
  (interactive)
  (throw 'exit nil))

;; Simulate character decoding by the keyboard coding system in the
;; current buffer (minibuffer).  As soon as a character is inserted,
;; it exits from minibuffer.

(defun isearch-with-keyboard-coding ()
  (interactive)
  (let ((after-change-functions '(isearch-exit-recursive-edit)))
    (recursive-edit))
  (exit-minibuffer))

;; Simulate the work of the current input method in the current buffer
;; (minibuffer).

(defun isearch-with-input-method ()
  (interactive)
  (let ((key (car unread-command-events))
	events)
    (setq unread-command-events (cdr unread-command-events)
	  events (funcall input-method-function key))
    ;; EVENTS is a list of events the input method has generated.  It
    ;; contains a character event and/or the special event
    ;; `compose-last-chars'.  We extract only character events and
    ;; insert the corresponding characters.
    (while events
      (if (integerp (car events)) (insert (car events)))
      (setq events (cdr events)))
    (exit-minibuffer)))

;;;###autoload
(defun isearch-process-search-multibyte-characters (last-char)
  (if (eq this-command 'isearch-printing-char)
      (let ((overriding-terminal-local-map nil)
	    (prompt (concat (isearch-message-prefix)))
	    (minibuffer-local-map isearch-minibuffer-local-map)
	    str)
	(if isearch-input-method-function
	    (let (;; Let input method work rather tersely.
		  (input-method-verbose-flag nil))
	      (setq unread-command-events
		    (cons 'with-input-method
			  (cons last-char unread-command-events))
		    ;; Inherit current-input-method in a minibuffer.
		    str (read-string prompt isearch-message nil nil t))
	      (if (not str)
		  ;; All inputs were deleted while the input method
		  ;; was working.
		  (setq str "")
		(setq str (substring str (length isearch-message)))
		(if (and (= (length str) 1)
			 (= (aref str 0) last-char)
			 (>= last-char 128))
		    ;; The input method couldn't handle LAST-CHAR.
		    (setq str nil)))))

	(if (and (not str) (keyboard-coding-system))
	    (setq unread-command-events
		  (cons 'with-keyboard-coding
			(cons last-char unread-command-events))
		  str (read-string prompt)))

	(if (and str (> (length str) 0))
	    (let ((unread-command-events nil))
	      (isearch-process-search-string str str))
	  (isearch-update)))
    (isearch-process-search-char last-char)))

;;; arch-tag: 1a90a6cf-2cb2-477a-814a-9ff895852822
;;; isearch-x.el ends here
