;;; tramp-adb.el --- Functions for calling Android Debug Bridge from Tramp

;; Copyright (C) 2011  Juergen Hoetzel

;; Author: Juergen Hoetzel <juergen@archlinux.org>
;; Keywords: comm, processes

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(require 'tramp-sh)

(defcustom tramp-adb-sdk-dir "~/Android/sdk"
  "Set to the directory containing the Android SDK."
  :type 'string
  :group 'tramp-adb)

;;;###tramp-autoload
(defconst tramp-adb-method "adb"
  "*When this method name is used, forward all calls to Android Debug Bridge.")

(defconst tramp-adb-ls-errors (regexp-opt '("No such file or directory")))

;;;###tramp-autoload
(add-to-list 'tramp-methods `(,tramp-adb-method))

;;;###tramp-autoload
(add-to-list 'tramp-default-method-alist
	     (list "\\`adb" nil tramp-adb-method))

;;;###tramp-autoload
(add-to-list 'tramp-foreign-file-name-handler-alist
	     (cons 'tramp-adb-file-name-p 'tramp-adb-file-name-handler))

(defconst tramp-adb-file-name-handler-alist
  '((directory-file-name . tramp-handle-directory-file-name)
    (dired-uncache . tramp-handle-dired-uncache)
    (file-name-as-directory . tramp-handle-file-name-as-directory)
    (file-name-completion . tramp-handle-file-name-completion)
    (file-name-all-completions . tramp-adb-handle-file-name-all-completions)
    (file-attributes . tramp-adb-handle-file-attributes)
    (file-name-directory . tramp-handle-file-name-directory)
    (file-name-nondirectory . tramp-handle-file-name-nondirectory)
    (file-newer-than-file-p . tramp-handle-file-newer-than-file-p)
    (file-name-as-directory . tramp-handle-file-name-as-directory)
    (file-regular-p . tramp-handle-file-regular-p)
    (file-remote-p . tramp-handle-file-remote-p)
    (file-directory-p . tramp-adb-handle-file-directory-p)
    (file-symlink-p . tramp-handle-file-symlink-p)
    (file-exists-p . tramp-adb-handle-file-exists-p)
    (file-readable-p . tramp-handle-file-exists-p)
    (file-writable-p . tramp-adb-handle-file-writable-p)
    (file-local-copy . tramp-adb-handle-file-local-copy)
    (expand-file-name . tramp-adb-handle-expand-file-name)
    (find-backup-file-name . tramp-handle-find-backup-file-name)
    (directory-files . tramp-adb-handle-directory-files)
    (make-directory . tramp-adb-handle-make-directory)
    (delete-directory . tramp-adb-handle-delete-directory)
    (delete-file . tramp-adb-handle-delete-file)
    (load . tramp-handle-load)
    (insert-directory . tramp-adb-handle-insert-directory)
    (insert-file-contents . tramp-handle-insert-file-contents)
    (substitute-in-file-name . tramp-handle-substitute-in-file-name)
    (unhandled-file-name-directory . tramp-handle-unhandled-file-name-directory)
    (vc-registered . ignore)	;no  vc control files on Android devices
    (write-region . tramp-adb-handle-write-region)
    (rename-file . tramp-sh-handle-rename-file))
  "Alist of handler functions for Tramp ADB method.")

;;;###tramp-autoload
(defun tramp-adb-file-name-p (filename)
  "Check if it's a filename for ADB."
  (let ((v (tramp-dissect-file-name filename)))
    (string= (tramp-file-name-method v) tramp-adb-method)))

;;;###tramp-autoload
(defun tramp-adb-file-name-handler (operation &rest args)
  "Invoke the ADB handler for OPERATION.
First arg specifies the OPERATION, second arg is a list of arguments to
pass to the OPERATION."
  (let ((fn (assoc operation tramp-adb-file-name-handler-alist)))
    (if fn
	(save-match-data (apply (cdr fn) args))
      (tramp-run-real-handler operation args))))

(defun tramp-adb-handle-expand-file-name (name &optional dir)
  "Like `expand-file-name' for Tramp files."
  ;; If DIR is not given, use DEFAULT-DIRECTORY or "/".
  (setq dir (or dir default-directory "/"))
  ;; Unless NAME is absolute, concat DIR and NAME.
  (unless (file-name-absolute-p name)
    (setq name (concat (file-name-as-directory dir) name)))
  ;; If NAME is not a Tramp file, run the real handler.
  (if (not (tramp-tramp-file-p name))
      (tramp-run-real-handler 'expand-file-name (list name nil))
    ;; Dissect NAME.
    (with-parsed-tramp-file-name name nil
      (unless (tramp-run-real-handler 'file-name-absolute-p (list localname))
	(setq localname (concat "/" localname)))
      (let ((r (tramp-make-tramp-file-name "adb" nil nil localname )))
	(tramp-message v 5 "%s -> %s" name r)
	r))))

(defun tramp-adb-handle-file-directory-p (filename)
  "Like `file-directory-p' for Tramp files."
  (let (symlink (file-symlink-p filename))
    (if symlink
	(tramp-adb-handle-file-directory-p symlink)
      (and (file-exists-p filename)
	   (car (file-attributes filename))))))

(defun tramp-adb-handle-file-attributes (filename &optional id-format)
  "Like `file-attributes' for Tramp files."
  (unless id-format (setq id-format 'integer))
  (with-parsed-tramp-file-name filename nil
    (with-file-property v localname (format "file-attributes-%s" id-format)
      (tramp-adb-send-command
       v
       (format "ls -d -l %s" (tramp-shell-quote-argument localname)))
      (with-current-buffer (tramp-get-buffer v)
	(unless (string-match tramp-adb-ls-errors (buffer-string))
	  (tramp-adb-sh-fix-ls-outout)
	  (let* ((columns (split-string (buffer-string)))
		 (mod-string (nth 0 columns))
		 (is-dir (eq ?d (aref mod-string 0)))
		 (is-symlink (eq ?l (aref mod-string 0)))
		 (symlink-target (and is-symlink (cadr (split-string (buffer-string) "\\( -> \\|\n\\)"))))
		 (uid (nth 1 columns))
		 (gid (nth 2 columns))
		 (date (format "%s %s" (nth 4 columns) (nth 5 columns)))
		 (size (string-to-int (nth 3 columns))))
	    (list
	     (or is-dir symlink-target)
	     1 					;link-count
	     ;; no way to handle numeric ids in Androids ash
	     (if (eq id-format 'integer) 0 uid)
	     (if (eq id-format 'integer) 0 gid)
	     '(0 0) ; atime
	     (date-to-time date) ; mtime
	     '(0 0) ; ctime
	     size
	     mod-string
	     ;; fake
	     t 1 1)))))))

(defun tramp-adb--gnu-switches-to-ash
  (switches)
  "Almquist shell can't handle multiple arguments. Convert (\"-al\") to (\"-a\" \"-l\")"
  (split-string (apply 'concat (mapcar (lambda (s)
					 (replace-regexp-in-string "\\(.\\)"  " -\\1"
								   (replace-regexp-in-string "^-" "" s)))
				       ;; FIXME: Warning about removed switches (long and non-dash)
				       (remove-if (lambda (s)
						    (string-match  "\\(^--\\|^[^-]\\)" s)) switches)))))


(defun tramp-adb-handle-insert-directory
  (filename switches &optional wildcard full-directory-p)
  "Like `insert-directory' for Tramp files."
  (when (stringp switches)
    (setq switches (tramp-adb--gnu-switches-to-ash (split-string switches))))
  (with-parsed-tramp-file-name (expand-file-name filename) nil
    (when (member "-t" switches)
      (setq switches (delete "-t" switches))
      (tramp-message v 1 "adb: ls can't handle \"-t\" switch"))
    (let ((cmd (format "ls %s \"%s\"" (mapconcat 'identity switches " ")
		       localname)))
      (tramp-adb-send-command v cmd)
      (insert
       (with-current-buffer (tramp-get-buffer v)
	 (buffer-string)))
      (tramp-adb-sh-fix-ls-outout))))

(defun tramp-adb-sh-fix-ls-outout ()
  "Andorids ls command doesn't insert size column for directories: Emacs dired can't find files. Insert dummy 0 in empty size columns."
  (save-excursion
    (goto-char (point-min))
    (while (search-forward-regexp  "[[:space:]]\\([[:space:]][0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9][[:space:]]\\)"  nil t)
      (replace-match "0\\1" "\\1"  nil  ))))

(defun tramp-adb-handle-directory-files (dir &optional full match nosort files-only)
  "Like `directory-files' for Tramp files."
  (with-parsed-tramp-file-name dir nil
    (tramp-adb-send-command
     v (format "%s %s"
	       "ls"
	       (tramp-shell-quote-argument localname)))
    (with-current-buffer (tramp-get-buffer v)
      (remove-if (lambda (l) (string-match  "^[[:space:]]*$" l))
		 (split-string (buffer-string) "\n")))))

(defun tramp-adb-handle-make-directory (dir &optional parents)
  "Like `make-directory' for Tramp files."
  (setq dir (expand-file-name dir))
  (with-parsed-tramp-file-name dir nil
    (when parents
      (tramp-message v 5 "mkdir doesn't handle \"-p\" switch: mkdir \"%s\"" (tramp-shell-quote-argument localname)))
    (save-excursion
      (tramp-barf-unless-okay
       v (format "%s %s"
		 "mkdir"
		 (tramp-shell-quote-argument localname))
       "Couldn't make directory %s" dir)
    (tramp-flush-directory-property v (file-name-directory localname)))))

(defun tramp-adb-handle-delete-directory (directory &optional recursive)
  "Like `delete-directory' for Tramp files."
  (setq directory (expand-file-name directory))
  (with-parsed-tramp-file-name directory nil
    (tramp-flush-file-property v (file-name-directory localname))
    (tramp-flush-directory-property v localname)
    (tramp-barf-unless-okay
     v (format "%s %s"
	       (if recursive "rm -r" "rmdir")
	       (tramp-shell-quote-argument localname))
     "Couldn't delete %s" directory)))

(defun tramp-adb-handle-delete-file (filename &optional trash)
  "Like `delete-file' for Tramp files."
  (setq filename (expand-file-name filename))
  (with-parsed-tramp-file-name filename nil
    (tramp-flush-file-property v (file-name-directory localname))
    (tramp-flush-file-property v localname)
    (tramp-barf-unless-okay
     v (format "%s %s"
	       (or (and trash (tramp-get-remote-trash v)) "rm")
	       (tramp-shell-quote-argument localname))
     "Couldn't delete %s" filename)))

(defun tramp-adb-handle-file-name-all-completions (filename directory)
  "Like `file-name-all-completions' for Tramp files."
  (all-completions
   filename
   (with-parsed-tramp-file-name directory nil
     (with-file-property v localname "file-name-all-completions"
       (save-match-data
	 (mapcar
	  (lambda (f)
	    (if (file-directory-p f)
		(file-name-as-directory f)
	      f))
	  (directory-files directory)))))))

(defun tramp-adb-handle-file-local-copy (filename)
  "Like `file-local-copy' for Tramp files."
  (with-parsed-tramp-file-name filename nil
    (unless (file-exists-p filename)
      (tramp-error
       v 'file-error
       "Cannot make local copy of non-existing file `%s'" filename))
    (let* ((adb-program (expand-file-name "platform-tools/adb" (file-name-as-directory tramp-adb-sdk-dir)))
	   (tmpfile (tramp-compat-make-temp-file filename))
	   (fetch-command (concat adb-program " pull " (shell-quote-argument localname) " " (shell-quote-argument tmpfile))))
      (with-progress-reporter
	  v 3 (format "Fetching %s to tmp file %s, using command: %s" filename tmpfile fetch-command)
	(unless (shell-command  fetch-command)
	  ;;FIXME On Error we shall cleanup.
	  (delete-file tmpfile)
	  (tramp-error
	   v 'file-error "Cannot make local copy of file `%s'" filename)))
      tmpfile)))

(defun tramp-adb-handle-file-writable-p (filename)
  (with-parsed-tramp-file-name filename nil
    ;; missing "test" command on Android devices
    (tramp-message v 5 "not implemented yet (Assuming /data/data is writable) :%s" localname)
    (let ((rw-path "/data/data"))
      (and (>= (length localname) (length rw-path))
	   (string= (substring localname 0 (length rw-path))
		    rw-path)))))

(defun tramp-adb-handle-write-region
  (start end filename &optional append visit lockname confirm)
  "Like `write-region' for Tramp files."
  (setq filename (expand-file-name filename))
  (with-parsed-tramp-file-name filename nil
    (when append
      (tramp-error
       v 'file-error "Cannot append to file using Tramp (`%s')" filename))
    (when (and confirm (file-exists-p filename))
      (unless (y-or-n-p (format "File %s exists; overwrite anyway? "
				filename))
	(tramp-error v 'file-error "File not overwritten")))
    ;; We must also flush the cache of the directory, because
    ;; `file-attributes' reads the values from there.
    (tramp-flush-file-property v (file-name-directory localname))
    (tramp-flush-file-property v localname)
    (let* ((curbuf (current-buffer))
	   (tmpfile (tramp-compat-make-temp-file filename)))
      (tramp-run-real-handler
       'write-region
       (list start end tmpfile append 'no-message lockname confirm))
      (with-progress-reporter
	  v 3 (format "Moving tmp file %s to %s" tmpfile filename)
	(unwind-protect
	    (let ((e (tramp-adb-execute-adb-command "push" (shell-quote-argument tmpfile) (shell-quote-argument localname))))
	      (delete-file tmpfile)
	      (when e
		(tramp-error v 'file-error "Cannot write: `%s'" e)))))

      (unless (equal curbuf (current-buffer))
	(tramp-error
	 v 'file-error
	 "Buffer has changed from `%s' to `%s'" curbuf (current-buffer))))))

;;; Android doesn't provide test command

(defun tramp-adb-handle-file-exists-p (filename)
  "Like `file-exists-p' for Tramp files."
  (with-parsed-tramp-file-name filename nil
    (with-file-property v localname "file-exists-p"
      (tramp-adb-handle-file-attributes filename))))

;; Helper functions

(defun tramp-adb-execute-adb-command (&rest args)
  "Returns nil on success error-output on failure."
  (let ((adb-program (expand-file-name "platform-tools/adb" (file-name-as-directory tramp-adb-sdk-dir))))
    (with-temp-buffer
      (unless (zerop (apply 'call-process-shell-command adb-program nil t nil args))
	(buffer-string)))))

;; Connection functions

(defun tramp-adb-send-command (vec command)
  "Send the COMMAND to connection VEC.
Returns nil if there has been an error message from adb."
  (tramp-adb-maybe-open-connection vec)
  (tramp-message vec 6 "%s" command)
  (tramp-send-string vec command)
  ;; fixme: Race condition
  (tramp-adb-wait-for-output (tramp-get-connection-process vec))
  (with-current-buffer (tramp-get-connection-buffer vec)
    (save-excursion
      (goto-char (point-min))
      ;; we can't use stty to disable echo of command
      (delete-matching-lines (regexp-quote command)))))

(defun tramp-adb-wait-for-output (proc &optional timeout)
  "Wait for output from remote command."
  (unless (buffer-live-p (process-buffer proc))
    (delete-process proc)
    (tramp-error proc 'file-error "Process `%s' not available, try again" proc))
  (with-current-buffer (process-buffer proc)
    (if (tramp-wait-for-regexp proc timeout (regexp-quote tramp-end-of-output))
	(let (buffer-read-only)
	  (goto-char (point-min))
	  (when (search-forward tramp-end-of-output (point-at-eol) t)
	    (forward-line 1)
	    (delete-region (point-min) (point)))
	  ;; Delete the prompt.
	  (goto-char (point-max))
	  (search-backward tramp-end-of-output nil t)
	  (delete-region (point) (point-max)))
      (if timeout
	  (tramp-error
	   proc 'file-error
	   "[[Remote adb prompt `%s' not found in %d secs]]"
	   tramp-end-of-output timeout)
	(tramp-error
	 proc 'file-error
	 "[[Remote prompt `%s' not found]]" tramp-end-of-output)))))

(defun tramp-adb-maybe-open-connection (vec)
  "Maybe open a connection VEC.
Does not do anything if a connection is already open, but re-opens the
connection if a previous connection has died for some reason."
  (let* ((buf (tramp-get-buffer vec))
	 (p (get-buffer-process buf))
	 (adb-program (expand-file-name "platform-tools/adb" (file-name-as-directory tramp-adb-sdk-dir))))
    (unless
	(and p (processp p) (memq (process-status p) '(run open)))
      (save-match-data
	(when (and p (processp p)) (delete-process p))
	(with-progress-reporter vec 3 "Opening adb shell connection"
	  (let* ((coding-system-for-read 'utf-8-dos) ;is this correct?
		 (process-connection-type tramp-process-connection-type)
		 (p (let ((default-directory
			    (tramp-compat-temporary-file-directory)))
		      (start-process (tramp-buffer-name vec) (tramp-get-buffer vec) adb-program "shell"))))
	    (tramp-message
	     vec 6 "%s" (mapconcat 'identity (process-command p) " "))
	    ;; wait for initial prompty
	    (tramp-wait-for-regexp p nil "^[#\\$][[:space:]]+")
	    (unless (eq 'run (process-status p))
	      (tramp-error  vec 'file-error "Terminated!"))
	    (tramp-send-command
	     vec (format "PS1=%s" (shell-quote-argument tramp-end-of-output)) t)
	    (set-process-query-on-exit-flag p nil)))))))

(provide 'tramp-adb)
;;; tramp-adb.el ends here

