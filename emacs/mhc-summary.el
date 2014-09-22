;;; mhc-summary.el --- Summary major mode in MHC.

;; Author:  Yoshinari Nomura <nom@quickhack.net>,
;;          TSUCHIYA Masatoshi <tsuchiya@namazu.org>
;; Created: 2000/05/01
;; Revised: $Date$


;;; Commentary:

;; This file is a part of MHC.

;; This file consists of two parts: the first part contains MUA
;; backend functions, and the second part contains functions to make
;; summary contents.


;;; About MUA Backend:

;; In order to define new MUA backend, it is required to define these
;; methods.
;;
;;     (mhc-foo-summary-filename)
;;         Return the file name of the article on the current line in
;;         this summary buffer.
;;
;;     (mhc-foo-summary-display-article)
;;         Display the article on the current line in this buffer.
;;
;;     (mhc-foo-get-import-buffer GET-ORIGINAL)
;;         Return buffer visiting import article.  If GET-ORIGINAL,
;;         return it without MIME decode.
;;
;;     (mhc-foo-generate-summary-buffer DATE)
;;         Generate summary buffer of mailer, and change current
;;         buffer to it.  This function will be called at the top of
;;         mhc-scan-month.
;;
;;     (mhc-foo-insert-summary-contents INSERTER)
;;         Insert schedule with INSERTER.
;;
;;     (mhc-foo-summary-mode-setup DATE)
;;         Setup buffer as summary of mailer.  This function will be
;;         called at the end of mhc-scan-month.
;;
;;     (mhc-foo-highlight-message FOR-DRAFT)
;;         Hilight message in the current buffer.
;;         If FOR-DRAFT is non-nil, Hilight message as draft message."
;;
;;     (mhc-foo-eword-decode-string STRING)
;;         Decode encoded STRING.
;;
;;     (mhc-foo-decode-header)
;;         Decode encoded header.
;;
;; Define these methods appropriately, and put definitions as follows:
;;
;;    (provide 'mhc-foo)
;;    (put 'mhc-foo 'summary-filename        'mhc-foo-summary-filename)
;;    (put 'mhc-foo 'summary-display-article 'mhc-foo-summary-display-article)
;;    (put 'mhc-foo 'get-import-buffer       'mhc-foo-get-import-buffer)
;;    (put 'mhc-foo 'generate-summary-buffer 'mhc-foo-generate-summary-buffer)
;;    (put 'mhc-foo 'insert-summary-contents 'mhc-foo-insert-summary-contents)
;;    (put 'mhc-foo 'summary-mode-setup      'mhc-foo-summary-mode-setup)
;;    (put 'mhc-foo 'highlight-message       'mhc-foo-highlight-message)
;;    (put 'mhc-foo 'eword-decode-string     'mhc-foo-eword-decode-string)
;;    (put 'mhc-foo 'decode-header           'mhc-foo-decode-header)

;;; Code:

(require 'mhc-vars)
(require 'mhc-day)
(require 'mhc-compat)
(require 'mhc-schedule)
(require 'bytecomp)

;;; Global Variables:

(defcustom mhc-summary-language 'english
  "*Language of the summary."
  :group 'mhc
  :type '(choice (const :tag "English" english)
                 (const :tag "Japanese" japanese)))

(defcustom mhc-summary-use-cw nil
  "*If non-nil, insert `Calendar week number' instead of `Monday'."
  :group 'mhc
  :type '(choice (const :tag "Use" t)
                 (const :tag "No" nil)))

(defcustom mhc-use-week-separator t
  "*If non-nil insert separator in summary buffer."
  :group 'mhc
  :type 'boolean)

(defcustom mhc-summary-separator ?-
  "*Character of the separator as 'mhc-use-week-separator'."
  :group 'mhc
  :type 'character)

(defcustom mhc-use-month-separator t
  "*Insert separator in summary buffer for wide scope."
  :group 'mhc
  :type '(choice (const :tag "Insert (full width)" t)
                 (integer :tag "Insert (number of width)")
                 (const :tag "Not use" nil)))

(defcustom mhc-summary-month-separator ?=
  "*Character of the separator as 'mhc-use-month-separator'."
  :group 'mhc
  :type 'character)

(defcustom mhc-summary-string-conflict "[C]"
  "*String which indicates conflicts in summary buffer."
  :group 'mhc
  :type 'string)

(defcustom mhc-summary-string-recurrence "[R]"
  "*String which indicates recurrences in summary buffer."
  :group 'mhc
  :type 'string)

(defcustom mhc-summary-string-secret "[SECRET]"
  "*String which hides private subjects in summary buffer."
  :group 'mhc
  :type 'string)

(defcustom mhc-use-icon t
  "*If non-nil, schedule icon is used."
  :group 'mhc
  :type 'boolean)

(defcustom mhc-icon-path (if (fboundp 'locate-data-directory)
                             (locate-data-directory "mhc"))
  "*Icon path for MHC."
  :group 'mhc
  :type 'directory)

(defcustom mhc-icon-setup-hook nil
  "*A hook called after icon setup."
  :group 'mhc
  :type 'hook)

(defcustom mhc-summary-line-format
  (if (eq mhc-summary-language 'japanese)
      "%M%月%D%日%(%曜%) %b%e %c%i%s %p%l"
    "%M%/%D%S%W %b%e %c%i%s %p%l")
  "*A format string for summary line of MHC.
It may include any of the following format specifications
which are replaced by the given information:

%Y The year of the line if first line of the day.
%M The month of the line if first line of the day.
%D The day of the line if first line of the day.
%W The weekday name of the line if first line of the day.
%b Begin time.
%e End time (includes '-').
%c Warning string for conflict (See also `mhc-summary-string-conflict').
%i The icon for the schedule.
%s The subject of the schedule.
%p The priority of the schedule.
%l The location of the schedule.

%/ A slash character if first line of the day.
%( A left parenthesis character if first line of the day.
%) A right parenthesis character if first line of the day.
%S A space with face.

%年 The '年' of the line if first line of the day.
%月 The '月' of the line if first line of the day.
%日 The '日' of the line if first line of the day.
%曜 The japaneses weekday name of the line if first line of the day.
"
  :group 'mhc
  :type 'string)

;;; Internal Variable:

(defconst mhc-summary-major-mode-alist
  '((mew-summary-mode  . mhc-mew)
    (mew-virtual-mode  . mhc-mew)
    (wl-folder-mode    . mhc-wl)
    (wl-summary-mode   . mhc-wl)
    (gnus-group-mode   . mhc-gnus)
    (gnus-summary-mode . mhc-gnus)))

;; Internal Variables which are bound while inserting line:
(defvar mhc-tmp-day-face nil "a face for the day.")
(defvar mhc-tmp-dayinfo  nil "a dayinfo for the day.")
(defvar mhc-tmp-schedule nil "a schedule structure.")
(defvar mhc-tmp-begin    nil "begin time.")
(defvar mhc-tmp-end      nil "end time.")
(defvar mhc-tmp-conflict nil "non-nil if conflicted schedule.")
(defvar mhc-tmp-recurrence nil "non-nil if recurrence schedule.")
(defvar mhc-tmp-first    nil "non-nil if first schedule.")
(defvar mhc-tmp-private  nil "non-nil if private display mode.")
(defvar mhc-tmp-priority nil "a priority of the schedule.")
;; For TODO.
(defvar mhc-tmp-day      nil "the day.")
(defvar mhc-tmp-deadline nil "a schedule structure.")

;; Inserter (internal variable)
(defvar mhc-summary/line-inserter nil)

(defvar mhc-summary-line-format-alist
  '((?Y (mhc-summary/line-year-string)
        'face mhc-tmp-day-face)
    (?/ (if mhc-tmp-first "/" " ")
        'face mhc-tmp-day-face)
    (?S " " 'face mhc-tmp-day-face)
    (?M (mhc-summary/line-month-string)
        'face mhc-tmp-day-face)
    (?D (mhc-summary/line-day-string)
        'face mhc-tmp-day-face)
    (?W (mhc-summary/line-day-of-week-string)
        'face mhc-tmp-day-face)
    (?b (if (null mhc-tmp-begin)
            (make-string 5 ? )
          (format "%02d:%02d" (/ mhc-tmp-begin 60) (% mhc-tmp-begin 60)))
        'face 'mhc-summary-face-time)
    (?e (if (null mhc-tmp-end)
            (make-string 6 ? )
          (format "-%02d:%02d" (/ mhc-tmp-end 60) (% mhc-tmp-end 60)))
        'face 'mhc-summary-face-time)
    (?c (if mhc-tmp-conflict
            (if (and (mhc-use-icon-p) (mhc-icon-exists-p "conflict"))
                t
              mhc-summary-string-conflict))
        (if (and (mhc-use-icon-p) (mhc-icon-exists-p "conflict"))
            'icon 'face)
        (if (and (mhc-use-icon-p) (mhc-icon-exists-p "conflict"))
            (list "conflict") 'mhc-summary-face-conflict))
    (?r (if (and mhc-tmp-recurrence (not (string= "" mhc-tmp-recurrence)))
            (if (and (mhc-use-icon-p) (mhc-icon-exists-p "recurrence"))
                t
              mhc-summary-string-recurrence))
        (if (and (mhc-use-icon-p) (mhc-icon-exists-p "recurrence"))
            'icon 'face)
        (if (and (mhc-use-icon-p) (mhc-icon-exists-p "recurrence"))
            (list "recurrence") 'mhc-summary-face-recurrence))
    (?p (if mhc-tmp-priority
            (format "[%d]" mhc-tmp-priority))
        'face (cond
               ((null mhc-tmp-priority) nil)
               ((>= mhc-tmp-priority 80) 'mhc-summary-face-sunday)
               ((>= mhc-tmp-priority 50) 'mhc-summary-face-saturday)))
    (?i (not mhc-tmp-private) 'icon
        (if (mhc-schedule-in-category-p mhc-tmp-schedule "done")
            (delete "todo"
                    (copy-sequence (mhc-schedule-categories mhc-tmp-schedule)))
          (mhc-schedule-categories mhc-tmp-schedule)))
    (?s (mhc-summary/line-subject-string)
        'face
        (if mhc-tmp-private (mhc-face-category-to-face "Private")
          (mhc-face-category-to-face
           (car (mhc-schedule-categories mhc-tmp-schedule)))))
    (?l (mhc-summary/line-location-string)
        'face 'mhc-summary-face-location)
    (?\( (if mhc-tmp-first "(" " ")
         'face mhc-tmp-day-face)
    (?\) (if mhc-tmp-first ")" " ")
         'face mhc-tmp-day-face)
    (?年 (if mhc-tmp-first "年" (make-string 2 ? ))
         'face mhc-tmp-day-face)
    (?月 (if mhc-tmp-first "月" (make-string 2 ? ))
         'face mhc-tmp-day-face)
    (?日 (if mhc-tmp-first "日" (make-string 2 ? ))
         'face mhc-tmp-day-face)
    (?曜 (mhc-summary/line-day-of-week-ja-string)
         'face mhc-tmp-day-face))
  "An alist of format specifications that can appear in summary lines.
Each element is a list of following:
\(SPEC STRING-EXP PROP-TYPE PROP-VALUE\)
SPEC is a character for format specification.
STRING is an expression to get string to insert.
PROP-TYPE is an expression to get one of the two symbols `face' or `icon'.
It indicates a type of the property to put on the inserted string.
PROP-VALUE is the property value correspond to PROP-TYPE.
")


(defvar mhc-summary/cw-separator nil)
(defvar mhc-summary/cw-week nil)

;;; MUA Backend Functions:

;; (defun mhc-summary-mailer-type ()
;;   "Return mailer backend symbol using currently."
;;   (or (cdr (assq major-mode mhc-summary-major-mode-alist))
;;       (intern (concat "mhc-" (symbol-name mhc-mailer-package)))))

(defun mhc-summary-mailer-type () 'mhc-mua)

(defun mhc-summary/true (&rest args)
  "This is the dummy backend function, which always returns t."
  t)

(defsubst mhc-summary-get-function (operation &optional mailer)
  "Return appropriate function to do OPERATION for MAILER."
  (or (get (require (or mailer (mhc-summary-mailer-type))) operation)
      'mhc-summary/true))

(defsubst mhc-get-function  (operation)
  "Return appropriate function to do OPERATION."
  (or (get (require (intern (concat "mhc-" (symbol-name mhc-mailer-package))))
           operation)
      'mhc-summary/true))

(defsubst mhc-highlight-message (&optional for-draft)
  "Hilight message in the current buffer.
If optional argument FOR-DRAFT is non-nil, Hilight message as draft message."
  (funcall (mhc-get-function 'highlight-message) for-draft))

(defsubst mhc-eword-decode-string (string)
  "Decode encoded STRING."
  (funcall (mhc-get-function 'eword-decode-string) string))

(defsubst mhc-decode-header ()
  "Decode encoded header."
  (funcall (mhc-get-function 'decode-header)))

(defsubst mhc-summary-filename (&optional mailer)
  "Return file name of article on current line."
  (funcall (mhc-summary-get-function 'summary-filename mailer)))

(defsubst mhc-summary-display-article (&optional mailer)
  "Display article on current line."
  (funcall (mhc-summary-get-function 'summary-display-article mailer)))

(defsubst mhc-summary-get-import-buffer (&optional get-original mailer)
  "Return buffer to import article."
  (funcall (mhc-summary-get-function 'get-import-buffer mailer) get-original))

(defsubst mhc-summary-generate-buffer (date &optional mailer)
  "Generate buffer with summary mode of MAILER."
  (funcall (mhc-summary-get-function 'generate-summary-buffer mailer) date))

(defsubst mhc-summary-insert-contents (mhc-tmp-schedule
                                       mhc-tmp-private
                                       inserter
                                       &optional mailer)
  (if (eq 'direct mailer)
      (let ((mhc-use-icon nil))
        (mhc-summary-line-insert)
        (insert "\n"))
    (funcall (mhc-summary-get-function 'insert-summary-contents mailer)
             inserter)))

(defsubst mhc-summary-search-date (date)
  "Search day in the current buffer."
  (let (dayinfo)
    (goto-char (point-min))
    (while (and (not (eobp))
                (or (null (setq dayinfo
                                (get-text-property (point) 'mhc-dayinfo)))
                    (not (eq (mhc-day-date dayinfo) date))))
      (goto-char (next-single-property-change (point) 'mhc-dayinfo)))))

(defsubst mhc-summary-mode-setup (date &optional mailer)
  "Setup buffer as summary mode of MAILER."
  (funcall (mhc-summary-get-function 'summary-mode-setup mailer) date))

(defun mhc-summary-record (&optional mailer)
  "Return record on current line."
  (let ((filename (mhc-summary-filename mailer)))
    (if filename
        (mhc-parse-file filename))))

;;; Codes:
(defsubst mhc-summary/make-string (count character)
  (make-string (max 4 count) character))        ;; xxxx 4 ?

(defun mhc-summary/insert-separator (&optional wide str fixwidth)
  (let ((width (mhc-misc-get-width))
        hr)
    (if wide
        (if (stringp str)
            (let ((hr1 (make-string 4 mhc-summary-month-separator))     ;; xxxx 4 ?
                  hr2)
              (mhc-face-put hr1 'mhc-summary-face-month-separator)
              (mhc-face-put str 'mhc-summary-face-cw)
              (setq hr2 (mhc-summary/make-string (- width
                                                    (if (numberp mhc-use-month-separator)
                                                        mhc-calendar-width 2)
                                                    (length hr1) (length str))
                                                 mhc-summary-month-separator))
              (mhc-face-put hr2 'mhc-summary-face-separator)
              (setq hr (concat hr1 str hr2)))
          (setq hr (mhc-summary/make-string
                    (if (numberp mhc-use-month-separator)
                        mhc-use-month-separator
                      (- width 2))
                    mhc-summary-month-separator))
          (mhc-face-put hr 'mhc-summary-face-month-separator))
      (if (stringp str)
          (let ((hr1 (make-string 4 mhc-summary-separator))     ;; xxxx 4 ?
                hr2)
            (mhc-face-put hr1 'mhc-summary-face-separator)
            (mhc-face-put str 'mhc-summary-face-cw)
            (setq hr2 (mhc-summary/make-string (- width mhc-calendar-width
                                                  (length hr1) (length str))
                                               mhc-summary-separator))
            (mhc-face-put hr2 'mhc-summary-face-separator)
            (setq hr (concat hr1 str hr2)))
        (if fixwidth
            (setq hr (mhc-summary/make-string fixwidth mhc-summary-separator))
          (setq hr (mhc-summary/make-string (- width mhc-calendar-width)
                                            mhc-summary-separator)))
        (mhc-face-put hr 'mhc-summary-face-separator)))
    (insert hr "\n")))

(defvar mhc-summary/today nil)

(defun mhc-summary/insert-dayinfo (mhc-tmp-dayinfo mailer category-predicate secret)
  (let ((time-max -1)
        (schedules (mhc-day-schedules mhc-tmp-dayinfo))
        (mhc-tmp-first t)
        mhc-tmp-begin mhc-tmp-end
        mhc-tmp-location mhc-tmp-schedule
        mhc-tmp-conflict mhc-tmp-recurrence mhc-tmp-priority
        next-begin displayed)
    (if schedules
        (progn
          (while schedules
            (if (funcall category-predicate (car schedules))
                (progn
                  (setq mhc-tmp-begin (mhc-schedule-time-begin (car schedules))
                        mhc-tmp-end (mhc-schedule-time-end (car schedules))
                        mhc-tmp-priority (mhc-schedule-priority
                                          (car schedules))
                        next-begin (if (car (cdr schedules))
                                       (mhc-schedule-time-begin
                                        (car (cdr schedules))))
                        mhc-tmp-conflict (or (and mhc-tmp-end next-begin
                                                  (< next-begin mhc-tmp-end))
                                             (and mhc-tmp-begin time-max
                                                  (< mhc-tmp-begin time-max)))
                        mhc-tmp-recurrence (mhc-schedule-recurrence-tag (car schedules)))
                  (if mhc-tmp-end (setq time-max (max mhc-tmp-end time-max)))
                  (setq displayed t)
                  (mhc-summary-insert-contents
                   (car schedules)
                   (and secret
                        (mhc-schedule-in-category-p
                         (car schedules) mhc-category-as-private))
                   'mhc-summary-line-insert
                   mailer)
                  (setq mhc-tmp-first nil)))
            (setq schedules (cdr schedules)))
          (if (not displayed)
              (mhc-summary-insert-contents nil secret
                                           'mhc-summary-line-insert
                                           mailer)))
      (mhc-summary-insert-contents nil secret
                                   'mhc-summary-line-insert
                                   mailer))))


(defun mhc-summary-make-contents
  (dayinfo-list from to mailer &optional category-predicate secret)
  (let (todo-list overdue deadline mhc-tmp-day)
    (setq mhc-summary/today (mhc-date-now))
    (while dayinfo-list
      (if (or (mhc-date< (mhc-day-date (car dayinfo-list)) from)
              (mhc-date> (mhc-day-date (car dayinfo-list)) to))
          ()
        (mhc-summary/insert-dayinfo
         (car dayinfo-list) mailer
         (or category-predicate mhc-default-category-predicate-sexp)
         secret)
        (and mhc-use-week-separator
             (eq (mhc-day-day-of-week (car dayinfo-list))
                 (mhc-end-day-of-week))
             (> (length dayinfo-list) 1)
             (mhc-summary/insert-separator
              nil
              (when mhc-summary/cw-separator
                (format " CW %d " (mhc-date-cw
                                   (mhc-date++ (mhc-day-date (car dayinfo-list)))))))))
      (setq dayinfo-list (cdr dayinfo-list)))))


(defun mhc-summary/line-year-string ()
  (if mhc-tmp-first
      (format "%4d" (mhc-day-year mhc-tmp-dayinfo))
    (make-string 2 ? )))


(defun mhc-summary/line-month-string ()
  (if mhc-tmp-first
      (format "%02d" (mhc-day-month mhc-tmp-dayinfo))
    (make-string 2 ? )))


(defun mhc-summary/line-day-string ()
  (if mhc-tmp-first
      (format "%02d" (mhc-day-day-of-month mhc-tmp-dayinfo))
    (make-string 2 ? )))


(defun mhc-summary/line-day-of-week-string ()
  (if mhc-tmp-first
      (let ((week (mhc-day-day-of-week mhc-tmp-dayinfo)))
        (if (and mhc-summary/cw-week (= week 1) )
            (format "%3s"
                    (format "w%d" (mhc-date-cw (mhc-day-date mhc-tmp-dayinfo))))
          (aref ["Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"] week)))
    (make-string 3 ? )))

(defun mhc-summary/line-day-of-week-ja-string ()
  (if mhc-tmp-first
      (let ((week (mhc-day-day-of-week mhc-tmp-dayinfo)))
        (if (and mhc-summary/cw-week(= week 1) )
            (format "%2d" (mhc-date-cw (mhc-day-date mhc-tmp-dayinfo)))
          (aref ["日" "月" "火" "水" "木" "金" "土"] week)))
    (make-string 2 ? )))


(defun mhc-summary/line-subject-string ()
  (if mhc-tmp-private
      (and mhc-tmp-schedule mhc-summary-string-secret)
    (or (mhc-schedule-subject mhc-tmp-schedule) "")))


(defun mhc-summary/line-location-string ()
  (let ((location (mhc-schedule-location mhc-tmp-schedule)))
    (and (not mhc-tmp-private)
         location
         (> (length location) 0)
         (concat "[" location "]"))))


;;; Line format parsing

(defmacro mhc-line-insert (string)
  `(and (stringp ,string) (insert ,string)))

(defun mhc-line-parse-format (format spec-alist)
  (let ((f (mhc-string-to-char-list format))
        inserter entry)
    (setq inserter (list 'let (list 'pos)))
    (while f
      (if (eq (car f) ?%)
          (progn
            (setq f (cdr f))
            (if (eq (car f) ?%)
                (setq inserter (append inserter (list (list 'insert ?%))))
              (setq entry (assq (car f) spec-alist))
              (unless entry
                (error "Unknown format spec %%%c" (car f)))
              (setq inserter
                    (append inserter
                            (list (list 'setq 'pos (list 'point)))
                            (list (list 'mhc-line-insert
                                        (nth 1 entry)))
                            (and
                             (nth 2 entry)
                             (list
                              (append (cond
                                       ((eq (eval (nth 2 entry)) 'face)
                                        (list 'put-text-property
                                              'pos (list 'point)
                                              (list 'quote 'face)
                                              (nth 3 entry)))
                                       ((eq (eval (nth 2 entry)) 'icon)
                                        (list 'if
                                              (nth 1 entry)
                                              (list
                                               'and
                                               (list 'mhc-use-icon-p)
                                               (list 'mhc-put-icon
                                                     (nth 3 entry)))))))))))))
        (setq inserter (append inserter (list (list 'insert (car f))))))
      (setq f (cdr f)))
    inserter))


(defmacro mhc-line-inserter-setup (inserter format alist)
  `(let (byte-compile-warnings)
     (setq ,inserter
	   (byte-compile
	    (list 'lambda ()
		  (mhc-line-parse-format ,format ,alist))))
     (when (get-buffer "*Compile-Log*")
       (bury-buffer "*Compile-Log*"))
     (when (get-buffer "*Compile-Log-Show*")
       (bury-buffer "*Compile-Log-Show*"))))


(defun mhc-summary-line-inserter-setup ()
  "Setup MHC summary and line inserter."
  (interactive)
  (if (and (called-interactively-p 'interactive)
           (mhc-use-icon-p))
      (call-interactively 'mhc-icon-setup))
  (setq mhc-summary/cw-separator (and mhc-summary-use-cw
                                      mhc-use-week-separator
                                      (eq mhc-start-day-of-week 1)))
  (setq mhc-summary/cw-week (and mhc-summary-use-cw
                                 (not mhc-summary/cw-separator)))
  (mhc-line-inserter-setup
   mhc-summary/line-inserter
   mhc-summary-line-format
   mhc-summary-line-format-alist))


(defun mhc-summary-line-insert ()
  "Insert summary line."
  (let ((mhc-tmp-day-face (cond
                           ((mhc-schedule-in-category-p
                             mhc-tmp-schedule "holiday")
                            'mhc-category-face-holiday)
                           ((eq (mhc-day-day-of-week
                                 mhc-tmp-dayinfo) 0)
                            'mhc-summary-face-sunday)
                           ((eq (mhc-day-day-of-week mhc-tmp-dayinfo) 6)
                            'mhc-summary-face-saturday)
                           (t 'mhc-summary-face-default)))
        (pos (point)))
    (if (mhc-date= (mhc-day-date mhc-tmp-dayinfo) (mhc-date-now))
        (setq mhc-tmp-day-face (mhc-face-get-today-face mhc-tmp-day-face)))
    (funcall mhc-summary/line-inserter)
    (put-text-property pos (point) 'mhc-dayinfo mhc-tmp-dayinfo)))


(defvar mhc-summary-mode-map nil)

;; (unless mhc-summary-mode-map
  (setq mhc-summary-mode-map (make-sparse-keymap))
  (define-key mhc-summary-mode-map " " 'mhc-summary-scroll-message-forward)
  (define-key mhc-summary-mode-map (kbd "DEL") 'mhc-summary-scroll-message-backward)
  (define-key mhc-summary-mode-map "." 'mhc-summary-display)
  (define-key mhc-summary-mode-map "\C-m" 'mhc-summary-scroll-message-line-forward)
  (define-key mhc-summary-mode-map "v" 'mhc-summary-toggle-display-message)

  (define-key mhc-summary-mode-map "g" 'mhc-goto-month)
  (define-key mhc-summary-mode-map ">" 'mhc-goto-next-month)
  (define-key mhc-summary-mode-map "N" 'mhc-goto-next-year)
  (define-key mhc-summary-mode-map "<" 'mhc-goto-prev-month)
  (define-key mhc-summary-mode-map "P" 'mhc-goto-prev-year)

  (define-key mhc-summary-mode-map "s" 'mhc-rescan-month)
  (define-key mhc-summary-mode-map "d" 'mhc-delete)
  (define-key mhc-summary-mode-map "c" 'mhc-set-default-category)
  (define-key mhc-summary-mode-map "?" 'mhc-calendar)
  (define-key mhc-summary-mode-map "t" 'mhc-calendar-toggle-insert-rectangle)
  (define-key mhc-summary-mode-map "E" 'mhc-edit)
  (define-key mhc-summary-mode-map "M" 'mhc-modify)

  (define-key mhc-summary-mode-map "n" 'mhc-summary-display-next)
  (define-key mhc-summary-mode-map "p" 'mhc-summary-display-previous)
  (define-key mhc-summary-mode-map "f" 'forward-char)
  (define-key mhc-summary-mode-map "b" 'backward-char)

  (define-key mhc-summary-mode-map "j" 'mhc-summary-display-next)
  (define-key mhc-summary-mode-map "k" 'mhc-summary-display-previous)
  (define-key mhc-summary-mode-map "l" 'forward-char)
  (define-key mhc-summary-mode-map "h" 'backward-char)
;; )

(defun mhc-summary-mode ()
  "Major mode for MHC summary.

\\{mhc-summary-mode-map}"
  (interactive)
  (setq major-mode 'mhc-summary-mode
        mode-name  "MHC")
  (setq mode-line-buffer-identification (propertized-buffer-identification
                                         "MHC: %12b"))
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (use-local-map mhc-summary-mode-map)
  (run-hooks 'mhc-summary-mode-hook))

(defun mhc-summary-display-message ()
  (interactive)
  (save-selected-window
    (mhc-summary-display-article)))

(defun mhc-summary-toggle-display-message ()
  (interactive)
  (if (mhc-message-visible-p)
      (mhc-message-delete-windows)
    (mhc-summary-display-message)))

(defvar mhc-message-file-name nil)
(make-variable-buffer-local 'mhc-message-file-name)

(defun mhc-message-set-file-name (file-name)
  (setq mhc-message-file-name file-name))

(defun mhc-message-visible-p (&optional file-name)
  "Return non-nil if MHC message is currently displaying, or nil if none."
  (and (get-buffer-window "*MHC message*")
       (or (null file-name)
           (save-selected-window
             (pop-to-buffer "*MHC message*")
             (and (stringp mhc-message-file-name)
                  (string= mhc-message-file-name file-name))))))

(defun mhc-message-delete-windows ()
  (delete-windows-on "*MHC message*"))

(defalias 'mhc-summary-display 'mhc-summary-display-message)

(defun mhc-summary-display-next ()
  (interactive)
  (forward-line)
  (if (mhc-message-visible-p)
      (mhc-summary-display)))

(defun mhc-summary-display-previous ()
  (interactive)
  (forward-line -1)
  (if (mhc-message-visible-p)
      (mhc-summary-display)))

(defun mhc-summary-scroll-message-line-forward ()
  (interactive)
  (mhc-summary-scroll-message-forward 1))

(defun mhc-summary-scroll-message-forward (&optional lines)
  (interactive)
  (mhc-summary-scroll-message 'forward lines))

(defun mhc-summary-scroll-message-backward (&optional lines)
  (interactive)
  (mhc-summary-scroll-message 'backward lines))

(defun mhc-summary-scroll-message (direction &optional lines)
  (interactive)
  (if (mhc-message-visible-p (mhc-summary-filename))
      (save-selected-window
        (pop-to-buffer "*MHC message*")
        (if (eq direction 'forward)
            (mhc-message-scroll-page-forward lines)
          (mhc-message-scroll-page-backward lines)))
    (mhc-summary-display-message)))

(provide 'mhc-summary)

;;; Copyright Notice:

;; Copyright (C) 1999, 2000 Yoshinari Nomura. All rights reserved.
;; Copyright (C) 2000 MHC developing team. All rights reserved.

;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions
;; are met:
;;
;; 1. Redistributions of source code must retain the above copyright
;;    notice, this list of conditions and the following disclaimer.
;; 2. Redistributions in binary form must reproduce the above copyright
;;    notice, this list of conditions and the following disclaimer in the
;;    documentation and/or other materials provided with the distribution.
;; 3. Neither the name of the team nor the names of its contributors
;;    may be used to endorse or promote products derived from this software
;;    without specific prior written permission.
;;
;; THIS SOFTWARE IS PROVIDED BY THE TEAM AND CONTRIBUTORS ``AS IS''
;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
;; FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
;; THE TEAM OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
;; INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
;; (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
;; SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
;; HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
;; STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
;; OF THE POSSIBILITY OF SUCH DAMAGE.

;;; mhc-summary.el ends here.
