(cl:in-package #:eclector.reader.test)

(in-suite :eclector.reader)

;;; Test customizing INTERPRET-SYMBOL

(defvar *mock-packages*)

(defclass mock-package ()
  ((%name :initarg :name :reader name)
   (%symbols :initarg :symbols :reader %symbols
             :initform (make-hash-table :test #'equal))))

(defclass mock-symbol ()
  ((%name :initarg :name :reader name)
   (%package :initarg :package :reader %package)))

(defun %make-symbol (name package)
  (make-instance 'mock-symbol :name name :package package))

(defun make-mock-packages ()
  (alexandria:alist-hash-table
   `((#1="CL" . ,(let ((package (make-instance 'mock-package :name #1#)))
                   (setf (gethash #2="NIL" (%symbols package))
                         (%make-symbol #2# package)
                         (gethash #3="LIST" (%symbols package))
                         (%make-symbol #3# package))
                   package))
     (#4="KEYWORD" . ,(make-instance 'mock-package :name #4#))
     (#5="BAR" . ,(let ((package (make-instance 'mock-package :name #5#)))
                    (setf (gethash #6="BAZ" (%symbols package))
                          (%make-symbol #6# package))
                    package)))
   :test #'equal))

(defclass mock-symbol-client ()
  ())

(defmethod eclector.reader:interpret-symbol
    ((client mock-symbol-client) input-stream
     (package-indicator null) symbol-name internp)
  (%make-symbol symbol-name nil))

(defmethod eclector.reader:interpret-symbol
    ((client mock-symbol-client) input-stream
     package-indicator symbol-name internp)
  (let ((package (case package-indicator
                   (:current (error "not implemented"))
                   (:keyword (gethash "KEYWORD" *mock-packages*))
                   (t (or (gethash package-indicator *mock-packages*)
                          (eclector.reader::%reader-error
                           input-stream 'eclector.reader:package-does-not-exist
                           :package-name package-indicator))))))
    (if internp
        (alexandria:ensure-gethash
         symbol-name (%symbols package)
         (%make-symbol symbol-name package))
        (or (gethash symbol-name (%symbols package))
            (eclector.reader::%reader-error
             input-stream 'eclector.reader:symbol-does-not-exist
             :package package
             :symbol-name symbol-name)))))

(test interpret-symbol/customize
  "Test customizing the behavior of INTERPRET-SYMBOL."

  (let ((*mock-packages* (make-mock-packages)))
    (mapc (lambda (input-expected)
            (destructuring-bind
                (input expected-package &optional expected-symbol)
                input-expected
              (flet ((do-it ()
                       (with-input-from-string (stream input)
                         (let ((eclector.reader:*client* (make-instance 'mock-symbol-client)))
                           (eclector.reader:read stream)))))
                (case expected-package
                  (eclector.reader:package-does-not-exist
                   (signals eclector.reader:package-does-not-exist (do-it)))
                  (eclector.reader:symbol-does-not-exist
                   (signals eclector.reader:symbol-does-not-exist (do-it)))
                  ((nil)
                   (let ((result (do-it)))
                     (is (null (%package result)))
                     (is (equal expected-symbol (name result)))))
                  (t
                   (let* ((result (do-it))
                          (expected-package (gethash expected-package
                                                     *mock-packages*))
                          (expected-symbol (gethash expected-symbol
                                                    (%symbols expected-package))))
                     (is (eq expected-symbol result))
                     (is (eq expected-package (%package result)))))))))

          '(;; Uninterned
            ("#:foo"    nil       "FOO")

            ;; Non-existent package
            ("baz:baz"  eclector.reader:package-does-not-exist)

            ;; Keyword
            (":foo"     "KEYWORD" "FOO")

            ;; COMMON-LISP package
            ("cl:nil"   "CL"      "NIL")
            ("cl:list"  "CL"      "LIST")

            ;; User package
            ("bar:baz"  "BAR"     "BAZ")
            ("bar:fez"  eclector.reader:symbol-does-not-exist)
            ("bar::fez" "BAR"     "FEZ")))))

;;; Test customizing FIND-CHARACTER

(defclass find-character-client ()
  ())

(defmethod eclector.reader:find-character
    ((client find-character-client) (name t))
  (if (string= name "NO_SUCH_CHARACTER")
      nil
      #\a))

(test find-character/customize
  "Test customizing the behavior of FIND-CHARACTER."

  (mapc (lambda (input-expected)
          (destructuring-bind (input expected) input-expected
            (flet ((do-it ()
                     (with-input-from-string (stream input)
                       (let ((eclector.reader:*client*
                               (make-instance 'find-character-client)))
                         (eclector.reader:read stream)))))
              (case expected
                (eclector.reader:unknown-character-name
                 (signals-printable eclector.reader:unknown-character-name
                   (do-it)))
                (t
                 (is (equal expected (do-it))))))))
        '(;; Errors
          ("#\\no_such_character" eclector.reader:unknown-character-name)
          ("#\\NO_SUCH_CHARACTER" eclector.reader:unknown-character-name)

          ;; Single character
          ("#\\a"                 #\a)
          ("#\\A"                 #\A)
          ("#\\b"                 #\b)
          ("#\\B"                 #\B)

          ;; Multiple characters
          ("#\\name"              #\a)
          ("#\\Name"              #\a)
          ("#\\NAME"              #\a))))

;;; Test customizing EVALUATE-EXPRESSION

(defclass evaluate-expression-client ()
  ())

(defmethod eclector.reader:evaluate-expression
    ((client evaluate-expression-client) (expression (eql 1)))
  (error "foo"))

(defmethod eclector.reader:evaluate-expression
    ((client evaluate-expression-client) (expression t))
  nil)

(test evaluate-expression/customize
  "Test customizing the behavior of EVALUATE-EXPRESSION."

  (mapc (lambda (input-expected)
          (destructuring-bind (input expected) input-expected
            (flet ((do-it ()
                     (with-input-from-string (stream input)
                       (let ((eclector.reader:*client*
                               (make-instance 'evaluate-expression-client)))
                         (eclector.reader:read stream)))))
              (case expected
                (eclector.reader:read-time-evaluation-error
                 (signals-printable eclector.reader:read-time-evaluation-error
                   (do-it)))
                (t
                 (is (equal expected (do-it))))))))
        '(;; Errors
          ("(1 #.1 3)"          eclector.reader:read-time-evaluation-error)
          ;; No errors
          ("(1 #.2 3)"          (1 nil 3))
          ("(1 #.(list #.2) 3)" (1 nil 3)))))

;;; Test customizing {CHECK,EVALUATE}-FEATURE-EXPRESSION

(defclass feature-expression-client ()
  ())

(defmethod eclector.reader:check-feature-expression
    ((client feature-expression-client)
     (feature-expression t))
  (or (typep feature-expression '(cons (eql :version-at-least) (cons string null)))
      (call-next-method)))

(defmethod eclector.reader:evaluate-feature-expression
    ((client feature-expression-client)
     (feature-expression (eql :my-special-feature)))
  (eclector.reader:check-feature-expression client feature-expression)
  t)

(defmethod eclector.reader:evaluate-feature-expression
    ((client feature-expression-client)
     (feature-expression cons))
  (case (first feature-expression)
    (:not
     (eclector.reader:check-feature-expression client feature-expression)
     (eclector.reader:evaluate-feature-expression
      client (second feature-expression)))
    (:version-at-least
     (eclector.reader:check-feature-expression client feature-expression)
     t)
    (t
     (call-next-method))))

(test evaluate-feature-expression/customize
  "Test customizing the behavior of EVALUATE-FEATURE-EXPRESSION."

  (mapc (lambda (input-expected)
          (destructuring-bind (input expected) input-expected
            (flet ((do-it ()
                     (with-input-from-string (stream input)
                       (let ((eclector.reader:*client*
                               (make-instance 'feature-expression-client)))
                         (eclector.reader:read stream)))))
              (case expected
                (eclector.reader:single-feature-expected
                 (signals-printable eclector.reader:single-feature-expected
                   (do-it)))
                (eclector.reader:feature-expression-type-error
                 (signals-printable eclector.reader:feature-expression-type-error
                   (do-it)))
                (t
                 (is (eq expected (do-it))))))))
        '(;; Errors
          ("#+(not a b)                1 2" eclector.reader:single-feature-expected)
          ("#+(version-at-least)       1 2" eclector.reader:feature-expression-type-error)
          ("#+(version-at-least 1)     1 2" eclector.reader:feature-expression-type-error)
          ;; No errors
          ("#+common-lisp              1 2" 1)
          ("#+(not common-lisp)        1 2" 1)
          ("#+my-special-feature       1 2" 1)
          ("#+(and my-special-feature) 1 2" 1)
          ("#+(version-at-least \"1\") 1 2" 1))))
