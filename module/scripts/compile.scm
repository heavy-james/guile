;;; Compile --- Command-line Guile Scheme compiler

;; Copyright 2005,2008,2009 Free Software Foundation, Inc.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this software; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301 USA

;;; Author: Ludovic Court�s <ludo@gnu.org>
;;; Author: Andy Wingo <wingo@pobox.com>

;;; Commentary:

;; Usage: compile [ARGS]
;;
;; A command-line interface to the Guile compiler.

;;; Code:

(define-module (scripts compile)
  #:use-module ((system base compile) #:select (compile-file))
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (srfi srfi-37)
  #:export (compile))


(define (fail . messages)
  (format (current-error-port)
	  (string-concatenate `("error: " ,@messages "~%")))
  (exit 1))

(define %options
  ;; Specifications of the command-line options.
  (list (option '(#\h "help") #f #f
                (lambda (opt name arg result)
		  (alist-cons 'help? #t result)))

	(option '(#\L "load-path") #t #f
		(lambda (opt name arg result)
		  (let ((load-path (assoc-ref result 'load-path)))
		    (alist-cons 'load-path (cons arg load-path)
				result))))
	(option '(#\o "output") #t #f
		(lambda (opt name arg result)
		  (if (assoc-ref result 'output-file)
		      (fail "`-o' option cannot be specified more than once")
		      (alist-cons 'output-file arg result))))

	(option '(#\O "optimize") #f #f
		(lambda (opt name arg result)
		  (alist-cons 'optimize? #t result)))
	(option '(#\f "from") #t #f
		(lambda (opt name arg result)
                  (if (assoc-ref result 'from)
                      (fail "`--from' option cannot be specified more than once")
                      (alist-cons 'from (string->symbol arg) result))))
	(option '(#\t "to") #t #f
		(lambda (opt name arg result)
                  (if (assoc-ref result 'to)
                      (fail "`--to' option cannot be specified more than once")
                      (alist-cons 'to (string->symbol arg) result))))))

(define (parse-args args)
  "Parse argument list @var{args} and return an alist with all the relevant
options."
  (args-fold args %options
             (lambda (opt name arg result)
               (format (current-error-port) "~A: unrecognized option" opt)
	       (exit 1))
             (lambda (file result)
	       (let ((input-files (assoc-ref result 'input-files)))
		 (alist-cons 'input-files (cons file input-files)
			     result)))

	     ;; default option values
             '((input-files)
	       (load-path))))


(define (compile . args)
  (let* ((options         (parse-args args))
         (help?           (assoc-ref options 'help?))
         (compile-opts    (if (assoc-ref options 'optimize?) '(#:O) '()))
         (from            (or (assoc-ref options 'from) 'scheme))
         (to              (or (assoc-ref options 'to) 'objcode))
	 (input-files     (assoc-ref options 'input-files))
	 (output-file     (assoc-ref options 'output-file))
	 (load-path       (assoc-ref options 'load-path)))
    (if (or help? (null? input-files))
        (begin
          (format #t "Usage: compile [OPTION] FILE...
Compile each Guile source file FILE into a Guile object.

  -h, --help           print this help message

  -L, --load-path=DIR  add DIR to the front of the module load path
  -o, --output=OFILE   write output to OFILE

  -f, --from=LANG      specify a source language other than `scheme'
  -t, --to=LANG        specify a target language other than `objcode'

Report bugs to <guile-user@gnu.org>.~%")
          (exit 0)))

    (set! %load-path (append load-path %load-path))

    (if (and output-file
             (or (null? input-files)
                 (not (null? (cdr input-files)))))
        (fail "`-o' option can only be specified "
              "when compiling a single file"))

    (for-each (lambda (file)
                (format #t "wrote `~A'\n"
                        (compile-file file
                                      #:output-file output-file
                                      #:from from
                                      #:to to
                                      #:opts compile-opts)))
              input-files)))

(define main compile)

;;; Local Variables:
;;; coding: latin-1
;;; End:
