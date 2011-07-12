;;; f90-interface-browser.el --- Parse and browse f90 interfaces

;; This file is NOT part of Emacs.

;; Copyright (C) 2011 Lawrence Mitchell <wence@gmx.li>
;; Filename: f90-interface-browser.el
;; Created: 2011-07-06

;; COPYRIGHT NOTICE

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
;; General Public License for more
;; details. http://www.gnu.org/copyleft/gpl.html
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs. If you did not, write to the Free Software
;; Foundation, Inc., 675 Mass Ave., Cambridge, MA 02139, USA.

;;; Commentary:
;; You write (or work on) large, modern fortran code bases.  These
;; make heavy use of function overloading and generic interfaces.  Your
;; brain is too small to remember what all the specialisers are
;; called.  Therefore, your editor should help you.

;; Load this file and tell it to parse all the fortran files in your
;; code base.  You can do this one directory at a time by calling
;; `f90-parse-interfaces-in-dir' (M-x f90-parse-interfaces-in-dir
;; RET).  Now you are able to browse (with completion) all defined
;; interfaces in your code by calling
;; `f90-browse-interface-specialisers'.  Alternatively, if `point' is
;; on a function or subroutine call, you can call
;; `f90-find-tag-interface' and you'll be shown a list of the
;; interfaces that match the (possibly typed) argument list of the
;; current function.
;; Derived types are also parsed, so that slot types of derived types
;; are given the correct type (rather than a UNION-TYPE) when arglist
;; matching.

;; The parsing is by no means complete, it does a half-hearted attempt
;; using regular expressions (now you have two problems) rather than
;; defining a grammar and doing full parsing.

;;; Code:

;;; Preamble
(require 'cl)
(require 'thingatpt)
(require 'f90)
(require 'etags)

(defstruct f90-interface
  (name "" :read-only t)
  (publicp nil)
  specialisers)

(defstruct f90-specialiser
  (name "" :read-only t)
  (type "")
  (arglist "")
  (location))

(defvar f90-interface-type nil)
(make-variable-buffer-local 'f90-interface-type)

(defvar f90-buffer-to-switch-to nil)
(make-variable-buffer-local 'f90-buffer-to-switch-to)

(defvar f90-invocation-marker nil)
(make-variable-buffer-local 'f90-invocation-marker)

(defvar f90-all-interfaces (make-hash-table :test 'equal)
  "Hash table populated with all known f90 interfaces.")

(defvar f90-types (make-hash-table :test 'equal)
  "Hash table populated with all known f90 derived types.")

;;; Inlineable utility functions

(defsubst f90-specialisers (name interfaces)
  "Return all specialisers for NAME in INTERFACES."
  (f90-interface-specialisers (f90-get-interface name interfaces)))

(defsubst f90-valid-interface-name (name)
  "Return non-nil if NAME is an interface name."
  (gethash name f90-all-interfaces))

(defsubst f90-count-commas (str)
  "Count commas in STR."
  (loop for c across str
        count (eq c ?\,)))

(defsubst f90-get-parsed-type-varname (type)
  "Return the variable name of TYPE."
  (car type))

(defsubst f90-get-parsed-type-typename (type)
  "Return the type name of TYPE."
  (cadr type))

(defsubst f90-get-parsed-type-modifiers (type)
  "Return the modifiers of TYPE."
  (cddr type))

(defsubst f90-get-type (type)
  "Return the struct definition corresponding to TYPE."
  (gethash (f90-get-parsed-type-typename type) f90-types))

(defsubst f90-get-slot-type (slot type)
  "Get the type of SLOT in TYPE."
  (let ((fn (intern-soft (format "f90-type.%s.%s"
                                 (f90-get-parsed-type-typename type) slot))))
    (when fn
      (funcall fn (f90-get-type type)))))

(defsubst f90-merge-into-tags-completion-table (ctable)
  "Merge interface completions in CTABLE into `tags-completion-table'."
  (let ((table (tags-completion-table)))
    (maphash (lambda (k v)
               (ignore v)
               (intern k table))
             ctable)
    table))

;;; User-visible routines

(defun f90-parse-interfaces-in-dir (dir)
  "Parse all Fortran 90 files in DIR to populate `f90-all-interfaces'."
  (interactive "DParse files in directory: ")
  (loop for file in (directory-files dir t "\\.\\(?:[fF]90\\|fpp\\)\\'")
        do (f90-parse-interfaces file f90-all-interfaces)))

(defun f90-find-tag-interface (name &optional match-sublist)
  "List all interfaces matching NAME.

Restricts list to those matching the (possibly typed) arglist of the
word at point.  For the description of MATCH-SUBLIST see
`f90-browse-interface-specialisers'."
  (interactive (let ((def (word-at-point)))
                 (list (completing-read
                        (format "Find interface/tag (default %s): " def)
                        (f90-merge-into-tags-completion-table
                         f90-all-interfaces)
                        nil t nil nil def)
                       current-prefix-arg)))
  (if (f90-valid-interface-name name)
      (f90-browse-interface-specialisers name (f90-arglist-types)
                                         match-sublist
                                         (point-marker))
    (find-tag name)))

(defun f90-browse-interface-specialisers (name &optional arglist-to-match
                                               match-sublist
                                               invocation-point)
  "Browse all interfaces matching NAME.

If ARGLIST-TO-MATCH is non-nil restrict to those interfaces that match
it.
If MATCH-SUBLIST is non-nil only restrict to those interfaces for
which ARGLIST-TO-MATCH is a sublist of the specialiser's arglist.

If INVOCATION-POINT is non-nil it should be a `point-marker'
indicating where we were called from, for jumping back to with
`pop-tag-mark'."
  (interactive (let ((def (word-at-point)))
                 (list (completing-read
                        (format "Interface%s: "
                                (if def
                                    (format " (default %s)" def)
                                  ""))
                        f90-all-interfaces
                        nil t nil nil def))))
  (let ((buf (current-buffer)))
    (or invocation-point (setq invocation-point (point-marker)))
    (with-current-buffer (get-buffer-create "*Interface Browser*")
      (let ((interface (f90-get-interface name f90-all-interfaces))
            (type nil)
            (n-specs 0))
        (setq buffer-read-only nil)
        (erase-buffer)
        (setq n-specs
              (loop for s being the hash-values of
                    (f90-interface-specialisers interface)
                    do (setq type (f90-specialiser-type s))
                    when (or (null arglist-to-match)
                             (f90-approx-arglist-match
                              arglist-to-match s match-sublist))
                    do (insert
                        (propertize
                         (concat
                          (propertize
                           (format "%s [defined in %s]\n    (%s)\n"
                                   (propertize (f90-specialiser-name s)
                                               'face 'bold)
                                   (let ((f (car
                                             (f90-specialiser-location s))))
                                     (format "%s/%s"
                                             (file-name-nondirectory
                                              (directory-file-name
                                               (file-name-directory f)))
                                             (file-name-nondirectory f)))
                                   (f90-fontify-arglist
                                    (f90-specialiser-arglist s)))
                           'f90-specialiser-location
                           (f90-specialiser-location s)
                           'f90-specialiser-name (f90-specialiser-name s)
                           'mouse-face 'highlight
                           'help-echo
                           "mouse-1: find definition in other window")
                          "\n")
                         'f90-specialiser-extent (f90-specialiser-name s)))
                    and count 1))
        (goto-char (point-min))
        (insert (format "Interfaces for %s:\n\n"
                        (f90-interface-name interface)))
        (when arglist-to-match
          (insert (format "%s\n%s\n\n"
                          (if (zerop n-specs)
                              "No interfaces matching arglist (intrinsic?):"
                            "Only showing interfaces matching arglist:")
                          (f90-fontify-arglist arglist-to-match))))
        (f90-interface-browser-mode)
        (setq f90-buffer-to-switch-to buf)
        (setq f90-interface-type type)
        (setq f90-invocation-marker invocation-point)
        (pop-to-buffer (current-buffer))))))

(defun f90-next-definition (&optional arg)
  "Go to the next ARG'th specialiser definition."
  (interactive "p")
  (unless arg
    (setq arg 1))
  (while (> arg 0)
    (goto-char (next-single-property-change
                (point)
                'f90-specialiser-extent
                nil (point-max)))
    (decf arg)))

(defun f90-previous-definition (&optional arg)
  "Go to the previous ARG'th specialiser definition."
  (interactive "p")
  (unless arg
    (setq arg 1))
  (while (> arg 0)
    (loop repeat 2
          do (goto-char (previous-single-property-change
                         (point)
                         'f90-specialiser-extent
                         nil (point-min))))
    (f90-next-definition 1)
    (decf arg)))

(defun f90-mouse-find-definition (e)
  "Visit the definition at the position of the event E."
  (interactive "e")
  (let ((win (posn-window (event-end e)))
        (point (posn-point (event-end e))))
    (when (not (windowp win))
      (error "No definition here"))
    (with-current-buffer (window-buffer win)
      (goto-char point)
      (f90-find-definition))))

(defun f90-quit-browser ()
  "Quit the interface browser."
  (interactive)
  (let ((buf f90-buffer-to-switch-to))
    (kill-buffer (current-buffer))
    (pop-to-buffer buf)))

(defun f90-find-definition ()
  "Visit the definition at `point'."
  (interactive)
  (let ((location (get-text-property (point) 'f90-specialiser-location))
        (name (get-text-property (point) 'f90-specialiser-name))
        (type f90-interface-type)
        (buf (current-buffer))
        buf-to)
    (if location
        (progn (ring-insert find-tag-marker-ring f90-invocation-marker)
               (find-file-other-window (car location))
               (setq buf-to (current-buffer))
               (goto-char (cadr location))
               ;; Try forwards then backwards near the recorded
               ;; location
               (or (re-search-forward (format "%s[ \t]+%s[ \t]*("
                                              type name) nil t)
                   (re-search-backward (format "%s[ \t]+%s[ \t]*("
                                               type name) nil t))
               (beginning-of-line)
               (recenter 0)
               (pop-to-buffer buf)
               (setq f90-buffer-to-switch-to buf-to))
      (error "No definition at point"))))

(defvar f90-interface-browser-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") 'f90-find-definition)
    (define-key map (kbd "<down>") 'f90-next-definition)
    (define-key map (kbd "TAB") 'f90-next-definition)
    (define-key map (kbd "<up>") 'f90-previous-definition)
    (define-key map (kbd "<backtab>") 'f90-previous-definition)
    (define-key map (kbd "q") 'f90-quit-browser)
    (define-key map (kbd "<mouse-1>") 'f90-mouse-find-definition)
    map)
  "Keymap for `f90-interface-browser-mode'.")

(define-derived-mode f90-interface-browser-mode fundamental-mode "IBrowse"
  "Major mode for browsing f90 interfaces."
  (setq buffer-read-only t)
  (set-buffer-modified-p nil))

;;; Show type definition

(defun f90-show-type-definition (type)
  "Show the definition of TYPE.

This formats the parsed definition of TYPE, rather than jumping to the
existing definition."
  (interactive (list (completing-read "Type: " f90-types nil t "type(")))
  (with-current-buffer (get-buffer-create "*Type definition*")
    (setq buffer-read-only nil)
    (erase-buffer)
    (let* ((type-struct (f90-get-type (list nil type)))
           (tname (and (string-match "\\`type(\\([^)]+\\))" type)
                       (match-string 1 type)))
           (fns (loop for name in (funcall (intern-soft
                                            (format "f90-type.%s.-varnames"
                                                    type))
                                           type-struct)
                      collect (intern-soft (format "f90-type.%s.%s"
                                                   type name)))))
      (insert (format "type %s\n" tname))
      (loop for fn in fns
            for parsed = (funcall fn type-struct)
                then (funcall fn type-struct)
            do
            (insert (format "  %s :: %s\n"
                            (f90-format-parsed-slot-type parsed)
                            (f90-get-parsed-type-varname parsed))))
      (insert (format "end type %s\n" tname))
      (goto-char (point-min))
      (f90-mode)
      (view-mode)
      (pop-to-buffer (current-buffer)))))

;;; Arglist matching/formatting

(defun f90-format-parsed-slot-type (type)
  "Turn a parsed TYPE into a valid f90 type declaration."
  (if (null type)
      "UNION-TYPE"
    ;; Ignore name
    (setq type (cdr type))
    (mapconcat 'identity (loop for a in type
                               if (and (consp a)
                                       (string= (car a) "dimension"))
                               collect (format "dimension(%s)"
                                               (mapconcat 'identity
                                                          (make-list (cdr a)
                                                                     ":")
                                                          ","))
                               else if (not
                                        (string-match
                                         "\\`intent(\\(?:in\\|out\\|inout\\))"
                                         a))
                               collect a)
               ", ")))

(defun f90-fontify-arglist (arglist)
  "Fontify ARGLIST using `f90-mode'."
  (with-temp-buffer
    (if (stringp arglist)
        (insert (format "%s :: foo\n" arglist))
      (insert (mapconcat (lambda (x)
                           (format "%s :: foo" (f90-format-parsed-slot-type x)))
                         arglist "\n")))
    (f90-mode)
    (font-lock-fontify-buffer)
    (goto-char (point-min))
    (mapconcat 'identity
               (loop while (not (eobp))
                     collect (buffer-substring (line-beginning-position)
                                               (- (line-end-position) 7))
                     do (forward-line 1))
               "; ")))


(defun f90-match-arglist-to-specialisers (arglist interface)
  "Return all matches to ARGLIST in the specialisers of INTERFACE."
  (let ((specialisers (f90-interface-specialisers interface)))
    (loop for spec being the hash-values of specialisers
          when (f90-approx-arglist-match arglist
                                         (f90-specialiser-arglist spec))
          collect spec)))

(defun f90-count-non-optional-args (arglist)
  "Count non-optional args in ARGLIST."
  (loop for arg in arglist
        count (not (member "optional" (f90-get-parsed-type-modifiers arg)))))

(defun f90-approx-arglist-match (arglist specialiser &optional match-sub-list)
  "Return non-nil if ARGLIST matches the arglist of SPECIALISER.

If MATCH-SUB-LIST is non-nil just require that ARGLIST matches the
first (length ARGLIST) args of SPECIALISER."
  (let* ((n-passed-args (length arglist))
         (spec-arglist (f90-specialiser-arglist specialiser))
         (n-spec-args (length spec-arglist))
         (n-required-args (f90-count-non-optional-args spec-arglist)))
    (when (or match-sub-list
              (and (<= n-required-args n-passed-args)
                   (<= n-passed-args n-spec-args)))
      (loop for arg in arglist
            for spec-arg in spec-arglist
            with match = nil
            unless (or (null arg)
                       (string= (f90-get-parsed-type-typename arg)
                                (f90-get-parsed-type-typename spec-arg)))
            do (return nil)
            finally (return t)))))

;;; Internal functions

(defun f90-clean-comments ()
  "Clean Fortran 90 comments from the current buffer."
  (save-excursion
    (goto-char (point-min))
    (set-syntax-table f90-mode-syntax-table)
    (while (not (eobp))
      (when (nth 4 (parse-partial-sexp (line-beginning-position) (point)))
        (delete-region (max (1- (point)) (line-beginning-position))
                       (line-end-position)))
      (forward-char 1))))

(defun f90-clean-continuation-lines ()
  "Splat Fortran continuation lines in the current buffer onto one line."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "&[ \t]*\n[ \t]*&?" nil t)
      (replace-match "" nil t))))

(defun f90-normalise-string (string)
  "Return a suitably normalised version of STRING."
  ;; Trim whitespace
  (when (string-match "\\`[ \t]*\\([^ \t]+\\)[ \t]*\\'" string)
    (setq string (match-string 1 string)))
  (downcase string))

(defun f90-get-interface (name &optional interfaces)
  "Get the interface with NAME from INTERFACES.

If INTERFACES is nil use `f90-all-interfaces' instead."
  (gethash name (or interfaces f90-all-interfaces)))

(defsetf f90-get-interface (name &optional interfaces) (val)
  `(setf (gethash ,name (or ,interfaces f90-all-interfaces)) ,val))

;;; Entry point to parsing routines

(defun f90-parse-interfaces (file existing)
  "Parse interfaces in FILE and merge into EXISTING interface data."
  (with-temp-buffer
    (let ((interfaces (make-hash-table :test 'equal))
          (fname (file-name-nondirectory file)))
      ;; Fiddle things for Fluidity sources
      (when (and (file-exists-p file)
                 (file-readable-p file)
                 (not (string-match "\\`Reference_count_interface" fname)))
        (insert-file-contents-literally file)
        (when (string-match "\\`Reference_count_\\([^\\.]+\\)\\.F90" fname)
          (insert-file-contents-literally
           (expand-file-name
            (format "Reference_count_interface_%s.F90"
                    (match-string 1 fname))
            (file-name-directory file))))
        ;; Easier if we don't have to worry about line wrap
        (f90-clean-comments)
        (f90-clean-continuation-lines)
        (goto-char (point-min))
        ;; Search forward for a named interface block
        (while (re-search-forward
                "^[ \t]*interface[ \t]+\\([^ \t\n]+\\)[ \t]*$" nil t)
          (let* ((name (match-string 1))
                 interface)
            (unless (string= name "")
              (setq interface (make-f90-interface :name name))
              (save-restriction
                ;; Figure out all the specialisers for this generic name
                (narrow-to-region
                 (point)
                 (re-search-forward
                  (format "[ \t]*end interface\\(?:[ \t]+%s\\)?[ \t]*$" name)
                  nil t))
                (f90-populate-specialisers interface))
              ;; Multiple interface blocks with same name (this seems to
              ;; be allowed).  In which case merge rather than overwrite.
              (if (f90-get-interface name interfaces)
                  (f90-merge-interface interface interfaces)
                (setf (f90-get-interface name interfaces) interface)))))
        (goto-char (point-min))
        ;; Parse type definitions
        (save-excursion
          (while (re-search-forward
                  "^[ \t]*type[ \t]+\\(?:[^ \t\n]+\\)[ \t]*$" nil t)
            (let ((beg (match-beginning 0)))
              (unless (re-search-forward "^[ \t]*end[ \t]+type.*$" nil t)
                (error "Unable to find end of type definition"))
              (save-restriction
                (narrow-to-region beg (match-beginning 0))
                (f90-parse-type-definition)))))

        ;; Now find out if an interface is public or private to the module
        (f90-set-public-attribute interfaces)

        ;; Now find the arglists corresponding to the interface (so we
        ;; can disambiguate) and record their location in the file.
        (loop for interface being the hash-values of interfaces
              do (when (f90-interface-specialisers interface)
                   (maphash (lambda (specialiser val)
                              (save-excursion
                                (goto-char (point-min))
                                (let ((thing (f90-argument-list specialiser)))
                                  (setf (f90-specialiser-arglist
                                         val)
                                        (cadr thing))
                                  (setf (f90-specialiser-location
                                         val)
                                        (list file (caddr thing)))
                                  (setf (f90-specialiser-type
                                         val)
                                        (car thing)))))
                            (f90-interface-specialisers interface))))
        ;; Finally merge these new interfaces into the existing data.
        (f90-merge-interfaces interfaces existing)))))

(defun f90-merge-interface (interface interfaces)
  "Merge INTERFACE into the existing set of INTERFACES."
  (let ((name (f90-interface-name interface))
        spec-name)
    (when (f90-interface-specialisers interface)
      (loop for val being the hash-values of
            (f90-interface-specialisers interface)
            do (setq spec-name (f90-specialiser-name val))
            (setf (gethash spec-name (f90-specialisers name interfaces))
                  val)))))

(defun f90-merge-interfaces (new existing)
  "Merge NEW interfaces into EXISTING ones."
  (maphash (lambda (name val)
             (if (gethash name existing)
                 (f90-merge-interface val existing)
               (setf (gethash name existing)
                     val)))
           new))

(defun f90-populate-specialisers (interface)
  "Find all specialisers for INTERFACE."
  (save-excursion
    (goto-char (point-min))
    (setf (f90-interface-specialisers interface)
          (make-hash-table :test 'equal))
    (while (search-forward "module procedure" nil t)
      (let ((names (buffer-substring-no-properties
                    (point)
                    (line-end-position))))
        (mapc (lambda (x)
                (setf (gethash x (f90-interface-specialisers interface))
                      (make-f90-specialiser :name x)))
              (split-string names "[, \n]+" t))))))

(defun f90-set-public-attribute (interfaces)
  "Set public/private flag on all INTERFACES."
  (save-excursion
    ;; Default public unless private is specified.
    (let ((public (not (save-excursion
                         (re-search-forward "^[ \t]*private[ \t]*$" nil t)))))
      (while (re-search-forward (format "^[ \t]*%s[ \t]+"
                                        (if public "private" "public"))
                                nil t)
        (let ((names (buffer-substring-no-properties
                      (match-end 0)
                      (line-end-position))))
          ;; Set default
          (maphash (lambda (k v)
                     (ignore k)
                     (setf (f90-interface-publicp v) public))
                   interfaces)
          ;; Override for those specified
          (mapc (lambda (name)
                  (let ((interface (f90-get-interface name interfaces)))
                    (when interface
                      (setf (f90-interface-publicp interface) (not public)))))
                (split-string names "[, \t]" t)))))))

;;; Type/arglist parsing
(defun f90-argument-list (name)
  "Return typed argument list of function or subroutine NAME."
  (save-excursion
    (when (re-search-forward
           (format "\\(function\\|subroutine\\)[ \t]+%s[ \t]*("
                   name)
           nil t)
      (let* ((point (match-beginning 0))
             (type (match-string 1))
             (args (f90-split-arglist (buffer-substring-no-properties
                                       (point)
                                       (f90-end-of-arglist)))))
        (list type (f90-arg-types args) point)))))

(defun f90-parse-type-definition ()
  "Parse a type definition at (or in front of) `point'."
  (let (type slots slot fn)
    (goto-char (point-min))
    (unless (re-search-forward "^[ \t]*type[ \t]+\\(.+?\\)[ \t]*$" nil t)
      (error "Trying parse a type but no type found"))
    (setq type (format "type(%s)" (match-string 1)))
    (while (not (eobp))
      (setq slot (f90-parse-single-type-declaration))
      (when slot
        (setf slots (nconc slot slots)))
      (forward-line 1))
    (eval (f90-make-type-struct type slots))
    (setq fn (intern-soft (format "make-f90-type.%s" type)))
    (unless fn
      (error "Something bad went wrong parsing type definition %s" type))
    (setf (gethash type f90-types) (funcall fn))))

(defun f90-make-type-struct (type slots)
  "Create a struct describing TYPE with SLOTS."
  (let ((struct-name (make-symbol (format "f90-type.%s" type)))
        (varnames (reverse (mapcar (lambda (x)
                                     (setq x (car x))
                                     (if (string-match "\\([^(]+\\)(" x)
                                         (match-string 1 x)
                                       x)) slots))))
    `(defstruct (,struct-name
                 (:conc-name ,(make-symbol (format "f90-type.%s." type))))
       (-varnames ',varnames :read-only t)
       ,@(loop for (name . rest) in slots
               if (string-match "\\([^(]+\\)(\\([^)]+\\))" name)
               do (progn (if (assoc "dimension" (cdr rest))
                             (setcdr (assoc "dimension" (cdr rest))
                                     (1+ (f90-count-commas
                                          (match-string 2 name))))
                           (push (cons "dimension"
                                       (1+ (f90-count-commas
                                            (match-string 2 name))))
                                 (cdr rest)))
                         (setq name (match-string 1 name)))
               collect `(,(make-symbol name) (cons ',name ',rest)
                         :read-only t)))))

(defun f90-arglist-types ()
  "Return the types of the arguments to the function at `point'."
  (save-excursion
    (let* ((e (save-excursion (f90-end-of-subprogram) (point)))
           (b (save-excursion (f90-beginning-of-subprogram) (point)))
           (str (buffer-substring-no-properties b e))
           (p (point))
           names)
      (with-temp-buffer
        (insert str)
        (goto-char (- p b))
        (setq p (point-marker))
        (f90-clean-continuation-lines)
        (goto-char p)
        (search-forward "(")
        (setq names (f90-split-arglist (buffer-substring
                                        (point)
                                        (f90-end-of-arglist))))
        (goto-char (point-min))
        (f90-arg-types names)))))

(defun f90-arg-types (names)
  "Given NAMES of arguments return their types.

This works even with derived type subtypes (e.g. if A is a type(foo)
with slot B of type REAL, then A%B is returned being a REAL)."
  (loop for arg in names
        for subspec = nil then nil
        if (string-match "\\`\\([^%]+?\\)[ \t]*%\\(.+\\)\\'" arg)
        do (setq subspec (match-string 2 arg)
                 arg (match-string 1 arg))
        collect (save-excursion
                  (save-restriction
                    (when (re-search-forward
                           (format "^[ \t]*\\([^!\n].+?\\)[ \t]*::.*\\<%s\\>"
                                   arg) nil t)
                      (goto-char (match-beginning 0))
                      (let ((type (assoc arg
                                         (f90-parse-single-type-declaration))))
                        (f90-get-type-subtype type subspec)))))))

(defun f90-get-type-subtype (type subspec)
  "Return the type of TYPE possibly including slot references in SUBSPEC."
  (cond ((null subspec)
         type)
        ((string-match "\\`\\([^%]+?\\)[ \t]*%\\(.+\\)\\'" subspec)
         (f90-get-type-subtype (f90-get-slot-type (match-string 1 subspec)
                                                  type)
                               (match-string 2 subspec)))
        (t
         (f90-get-slot-type subspec type))))

(defun f90-split-arglist (arglist)
  "Split ARGLIST into words.

Split based on top-level commas. e.g.

  (f90-split-arglist \"foo, bar, baz(quux, zot)\")
    => (\"foo\" \"bar\" \"baz(quux, zot)\")."
  (let ((level 0)
        b e
        ret)
    (with-temp-buffer
      (insert arglist "\n")
      (goto-char (point-min))
      (setq b (point))
      (while (not (eobp))
        (cond ((eq (char-after) ?\()
               (incf level))
              ((eq (char-after) ?\))
               (decf level))
              (t nil))
        (when (and (zerop level)
                   (or (eq (char-after) ?\,)
                       (eolp)))
          (setq e (point))
          (push (f90-normalise-string (buffer-substring b e)) ret)
          (setq b (1+ (point))))
        (forward-char))
      (nreverse ret))))

(defun f90-end-of-arglist ()
  "Find the end of the arglist at `point'."
  (save-excursion
    (let ((level 0))
      (while (> level -1)
        (cond ((eq (char-after) ?\()
               (incf level))
              ((eq (char-after) ?\))
               (decf level))
              (t nil))
        (forward-char)))
    (1- (point))))

(defun f90-parse-names-list (names)
  "Return a list of NAMES from the RHS of a :: type declaration."
  (let ((names-list (f90-split-arglist names)))
    (loop for name in names-list
          if (string-match "\\`\\([^=]+\\)[ \t]*=.*\\'" name)
          collect (f90-normalise-string (match-string 1 name))
          else
          collect (f90-normalise-string name))))

(defun f90-parse-single-type-declaration ()
  "Parse a single f90 type declaration at `point'.

Assumes that this has the form
  TYPENAME[, MODIFIERS]* :: NAME[, NAMES]*

NAMES can optionally have initialisation attached to them which is
dealt with correctly."
  (when (looking-at "^[ \t]*\\(.*?\\)[ \t]*::[ \t]*\\(.*\\)$")
    (let ((dec (match-string 1))
          (names (f90-parse-names-list (match-string 2))))
      (loop for name in names
            collect (cons name (f90-split-declaration dec))))))

(defun f90-split-declaration (dec)
  "Split and parse a type declaration DEC.

This takes the bit before the :: and returns a list of the typename
and any modifiers."
  (let ((things (f90-split-arglist dec)))
    (cons (car things)
          (loop for thing in (cdr things)
                if (string-match "dimension(\\([^)]+\\))" thing)
                collect (cons "dimension"
                              (1+ (f90-count-commas (match-string 1 thing))))
                else if (string-match "character([^)]+)" thing)
                collect (cons "character" "*")
                else
                collect thing))))

(provide 'f90-interface-browser)

;;; f90-interface-browser.el ends here
