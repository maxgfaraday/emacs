;;; quail/lrt.el --- Quail package for inputting Lao characters by LRT method

;; Copyright (C) 1997 Electrotechnical Laboratory, JAPAN.
;; Licensed to the Free Software Foundation.

;; Keywords: multilingual, input method, Lao, LRT.

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

;;; Code:

(require 'quail)
(require 'lao-util)

;; LRT (Lao Roman Transcription) input method accepts the following
;; key sequence:
;;	consonant [+ semi-vowel-sign-lo ] + vowel [+ maa-sakod ] [+ tone-mark ]

(defun quail-lao-update-translation (control-flag)
  (if (integerp control-flag)
      ;; Non-composable character typed.
      (setq quail-current-str
	    (buffer-substring (overlay-start quail-overlay)
			      (overlay-end quail-overlay))
	    unread-command-events
	    (string-to-list
	     (substring quail-current-key control-flag)))
    (let ((lao-str (lao-transcribe-roman-to-lao-string quail-current-key)))
      (if (> (aref lao-str 0) 255)
	  (setq quail-current-str lao-str)
	(or quail-current-str
	    (setq quail-current-str quail-current-key)))))
  control-flag)


(quail-define-package
 "lao-lrt" "Lao" "(1E(BR" t
 "Lao input method using LRT (Lao Roman Transcription).
`\\' (backslash) + number-key	=> (1p(B,(1q(B,(1r(B,...	LAO DIGIT ZERO, ONE, TWO, ...
`\\' (backslash) + `\\'		=> (1f(B		LAO KO LA (REPETITION)
`\\' (backslash) + `$'		=> (1O(B		LAO ELLIPSIS
"
 nil 'forget-last-selection 'deterministic 'kbd-translate 'show-layout
  nil nil nil 'quail-lao-update-translation nil t)

;; LRT (Lao Roman Transcription) input method accepts the following
;; key sequence:
;;	consonant [ semi-vowel-sign-lo ] vowel [ maa-sakod ] [ tone-mark ]

(quail-install-map
 (quail-map-from-table
  '((base-state (lao-transcription-consonant-alist . sv-state)
		lao-transcription-vowel-alist
		lao-transcription-tone-alist)
    (sv-state (lao-transcription-semi-vowel-alist . v-state) 
	      (lao-transcription-vowel-alist . mt-state))
    (v-state (lao-transcription-vowel-alist . mt-state))
    (mt-state (lao-transcription-maa-sakod-alist . t-state) 
	      lao-transcription-tone-alist)
    (t-state lao-transcription-tone-alist))))

;;; quail/lrt.el ends here
