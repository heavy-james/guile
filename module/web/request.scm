;;; HTTP request objects

;; Copyright (C)  2010 Free Software Foundation, Inc.

;; This library is free software; you can redistribute it and/or
;; modify it under the terms of the GNU Lesser General Public
;; License as published by the Free Software Foundation; either
;; version 3 of the License, or (at your option) any later version.
;;
;; This library is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; Lesser General Public License for more details.
;;
;; You should have received a copy of the GNU Lesser General Public
;; License along with this library; if not, write to the Free Software
;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
;; 02110-1301 USA

;;; Code:

(define-module (web request)
  #:use-module (rnrs bytevectors)
  #:use-module (rnrs io ports)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-9)
  #:use-module (web uri)
  #:use-module (web http)
  #:export (request?
            request-method
            request-uri
            request-version
            request-headers
            request-meta
            request-port
            
            read-request
            build-request
            write-request

            read-request-body/latin-1
            write-request-body/latin-1

            read-request-body/bytevector
            write-request-body/bytevector

            ;; General headers
            ;;
            request-cache-control
            request-connection
            request-date
            request-pragma
            request-trailer
            request-transfer-encoding
            request-upgrade
            request-via
            request-warning
            
            ;; Entity headers
            ;;
            request-allow
            request-content-encoding
            request-content-language
            request-content-length
            request-content-location
            request-content-md5
            request-content-range
            request-content-type
            request-expires
            request-last-modified
            
            ;; Request headers
            ;;
            request-accept
            request-accept-charset
            request-accept-encoding
            request-accept-language
            request-authorization
            request-expect
            request-from
            request-host
            request-if-match
            request-if-modified-since
            request-if-none-match
            request-if-range
            request-if-unmodified-since
            request-max-forwards
            request-proxy-authorization
            request-range
            request-referer
            request-te
            request-user-agent

            ;; Misc
            request-absolute-uri))


;;; {Character Encodings, Strings, and Bytevectors}
;;; 
;;; Requests are read from over the wire, and as such have to be treated
;;; very carefully.
;;;
;;; The header portion of the message is defined to be in a subset of
;;; ASCII, and may be processed either byte-wise (using bytevectors and
;;; binary I/O) or as characters in a single-byte ASCII-compatible
;;; encoding.
;;;
;;; We choose the latter, processing as strings in the latin-1
;;; encoding. This allows us to use all the read-delimited machinery,
;;; character sets, and regular expressions, shared substrings, etc.
;;;
;;; The characters in the header values may themselves encode other
;;; bytes or characters -- basically each header has its own parser. We
;;; leave that as a header-specific topic.
;;;
;;; The body is present if the content-length header is present. Its
;;; format and, if textual, encoding is determined by the headers, but
;;; its length is encoded in bytes. So we just slurp that number of
;;; characters in latin-1, knowing that the number of characters
;;; corresponds to the number of bytes, and then convert to a
;;; bytevector, perhaps for later decoding.
;;;

(define-record-type <request>
  (make-request method uri version headers meta port)
  request?
  (method request-method)
  (uri request-uri)
  (version request-version)
  (headers request-headers)
  (meta request-meta)
  (port request-port))

(define (bad-request message . args)
  (throw 'bad-request message args))

(define (non-negative-integer? n)
  (and (number? n) (>= n 0) (exact? n) (integer? n)))
                                    
(define (validate-headers headers)
  (if (pair? headers)
      (let ((h (car headers)))
        (if (pair? h)
            (let ((k (car h)) (v (cdr h)))
              (if (symbol? k)
                  (if (not (valid-header? k v))
                      (bad-request "Bad value for header ~a: ~s" k v))
                  (if (not (and (string? k) (string? v)))
                      (bad-request "Unknown header not a pair of strings: ~s"
                                   h)))
              (validate-headers (cdr headers)))
            (bad-request "Header not a pair: ~a" h)))
      (if (not (null? headers))
          (bad-request "Headers not a list: ~a" headers))))

(define* (build-request #:key (method 'GET) uri (version '(1 . 1))
                        (headers '()) port (meta '())
                        (validate-headers? #t))
  (cond
   ((not (and (pair? version)
              (non-negative-integer? (car version))
              (non-negative-integer? (cdr version))))
    (bad-request "Bad version: ~a" version))
   ((not (uri? uri))
    (bad-request "Bad uri: ~a" uri))
   ((and (not port) (memq method '(POST PUT)))
    (bad-request "Missing port for message ~a" method))
   ((not (list? meta))
    (bad-request "Bad metadata alist" meta))
   (else
    (if validate-headers?
        (validate-headers headers))))
  (make-request method uri version headers meta port))

(define* (read-request port #:optional (meta '()))
  (set-port-encoding! port "ISO-8859-1")
  (call-with-values (lambda () (read-request-line port))
    (lambda (method uri version)
      (make-request method uri version (read-headers port) meta port))))

;; FIXME: really return a new request?
(define (write-request r port)
  (write-request-line (request-method r) (request-uri r)
                      (request-version r) port)
  (write-headers (request-headers r) port)
  (display "\r\n" port)
  (if (eq? port (request-port r))
      r
      (make-request (request-method r) (request-uri r) (request-version r)
                    (request-headers r) (request-meta r) port)))

;; Probably not what you want to use "in production". Relies on one byte
;; per char because we are in latin-1 encoding.
;;
(define (read-request-body/latin-1 r)
  (let ((nbytes (request-content-length r)))
    (and nbytes
         (let ((buf (make-string nbytes)))
           (read-delimited! "" buf (request-port r))
           buf))))

;; Likewise, assumes that body can be written in the latin-1 encoding,
;; and that the latin-1 encoding is what is expected by the server.
;;
(define (write-request-body/latin-1 r body)
  (display body (request-port r)))

(define (read-request-body/bytevector r)
  (let ((nbytes (request-content-length r)))
    (and nbytes
         (let ((bv (get-bytevector-n (request-port r) nbytes)))
           (if (= (bytevector-length bv) nbytes)
               bv
               (bad-request "EOF while reading request body: ~a bytes of ~a"
                            (bytevector-length bv) nbytes))))))

(define (write-request-body/bytevector r bv)
  (put-bytevector (request-port r) bv))

(define-syntax define-request-accessor
  (lambda (x)
    (syntax-case x ()
      ((_ field)
       #'(define-request-accessor field #f))
      ((_ field def) (identifier? #'field)
       #`(define* (#,(datum->syntax
                      #'field
                      (symbol-append 'request- (syntax->datum #'field)))
                   request
                   #:optional (default def))
           (cond
            ((assq 'field (request-headers request)) => cdr)
            (else default)))))))

;; General headers
;;
(define-request-accessor cache-control '())
(define-request-accessor connection '())
(define-request-accessor date #f)
(define-request-accessor pragma '())
(define-request-accessor trailer '())
(define-request-accessor transfer-encoding '())
(define-request-accessor upgrade '())
(define-request-accessor via '())
(define-request-accessor warning '())

;; Entity headers
;;
(define-request-accessor allow '())
(define-request-accessor content-encoding '())
(define-request-accessor content-language '())
(define-request-accessor content-length #f)
(define-request-accessor content-location #f)
(define-request-accessor content-md5 #f)
(define-request-accessor content-range #f)
(define-request-accessor content-type #f)
(define-request-accessor expires #f)
(define-request-accessor last-modified #f)

;; Request headers
;;
(define-request-accessor accept '())
(define-request-accessor accept-charset '())
(define-request-accessor accept-encoding '())
(define-request-accessor accept-language '())
(define-request-accessor authorization #f)
(define-request-accessor expect '())
(define-request-accessor from #f)
(define-request-accessor host #f)
;; Absence of an if-directive appears to be different from `*'.
(define-request-accessor if-match #f)
(define-request-accessor if-modified-since #f)
(define-request-accessor if-none-match #f)
(define-request-accessor if-range #f)
(define-request-accessor if-unmodified-since #f)
(define-request-accessor max-forwards #f)
(define-request-accessor proxy-authorization #f)
(define-request-accessor range #f)
(define-request-accessor referer #f)
(define-request-accessor te '())
(define-request-accessor user-agent #f)

;; Misc accessors
(define* (request-absolute-uri r #:optional default-host default-port)
  (let ((uri (request-uri r)))
    (if (uri-host uri)
        uri
        (let ((host
               (or (request-host r)
                   (if default-host
                       (cons default-host default-port)
                       (bad-request
                        "URI not absolute, no Host header, and no default: ~s"
                        uri)))))
          (build-uri (uri-scheme uri)
                     #:host (car host)
                     #:port (cdr host)
                     #:path (uri-path uri)
                     #:query (uri-query uri)
                     #:fragment (uri-fragment uri))))))