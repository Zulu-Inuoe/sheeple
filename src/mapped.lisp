(in-package :cl-user)

;;; some utils copied from utils.lisp

(defun ensure-list (x)
  "X if X is a list, otherwise (list X)."
  (if (listp x) x (list x)))

(defmacro fun (&body body)
  "This macro puts the FUN back in FUNCTION."
  `(lambda (&optional _) (declare (ignorable _)) ,@body))

(defmacro aif (test-form then-form &optional else-form)
  `(let ((it ,test-form))
     (if it ,then-form ,else-form)))

(defmacro awhen (test-form &body body)
  `(aif ,test-form (progn ,@body)))

;;; and some new ones!

(declaim (inline aconsf-helper))
(defun aconsf-helper (alist key value)
  (acons key value alist))

(define-modify-macro aconsf (key value)
  aconsf-helper
  "CONS is to PUSH as ACONS is to ACONSF; it pushes (cons KEY VALUE) to the PLACE.")

(defmacro check-list-type (list typespec &optional string)
  "Calls CHECK-TYPE with each element of LIST, with TYPESPEC and STRING."
  (let ((var (gensym)))
    `(dolist (,var ,list)
       ;; Evaluates STRING multiple times, due to lazyness and spec ambiguity. - Adlai
       (check-type ,var ,typespec ,@(when string `(,string))))))

(defmacro define-print-object (((object class) &key (identity t) (type t)) &body body)
  (let ((stream (gensym)))
    `(defmethod print-object ((,object ,class) ,stream)
      (print-unreadable-object (,object ,stream :type ,type :identity ,identity)
        (let ((*standard-output* ,stream)) ,@body)))))

;; Now for the code

(deftype property-name ()
  "A valid name for an object's property"
  'symbol)

(defstruct (mold (:conc-name   mold-)
                 (:predicate   moldp)
                 (:constructor make-mold)
                 (:copier      copy-mold))
  (parents        nil :read-only t)
  (properties     nil :read-only t)
  (hierarchy-list nil)
  (sub-molds      nil)
  (transitions    nil))

(define-print-object ((mold mold)))

(defstruct (object (:conc-name   %object-)
                   (:predicate   objectp)
                   (:constructor %make-object)
                   (:copier      %copy-object))
  mold property-values roles)

;;; This condition framework is straight from conditions.lisp

(define-condition mold-condition ()
  ((format-control :initarg :format-control :reader mold-condition-format-control))
  (:report (lambda (condition stream)
             (apply #'format stream (mold-condition-format-control condition)))))

(defmacro define-mold-condition (name super (&optional string &rest args)
                                    &rest condition-options)
  (let (reader-names)
    `(define-condition ,name ,(ensure-list super)
       ,(loop for arg in args for reader = (intern (format nil "~A-~A" name arg))
           collect
             `(,arg :initarg ,(intern (symbol-name arg) :keyword) :reader ,reader)
           do (push reader reader-names))
       (:report
        (lambda (condition stream)
          (funcall #'format stream (mold-condition-format-control condition)
                   ,@(mapcar #'(lambda (reader) `(,reader condition))
                             (nreverse reader-names)))))
       (:default-initargs :format-control ,string
         ,@(cdr (assoc :default-initargs condition-options)))
       ,@(remove :default-initargs condition-options :key #'car))))

(define-mold-condition mold-warning (mold-condition warning) ())
(define-mold-condition mold-error (mold-condition error) ())

;;; Now for an original condition:

(define-mold-condition mold-collision mold-error
  ("Can't link ~A, because doing so would conflict with the already-linked ~A."
   new-mold collision-mold))

;;; And now for some code:

(defun find-transition (mold property-name)
  "Returns the mold which adds a property named PROPERTY-NAME to MOLD.
If no such mold exists, returns NIL."
  (cdr (assoc property-name (mold-transitions mold) :test 'eq)))

;;; TODO: ensure-transition-by-property  - Adlai

(defun add-transition-by-property (from-mold property-name to-mold)
  "Adds a link from FROM-MOLD to TO-MOLD, indexed by PROPERTY-NAME.
If a new link was created, FROM-MOLD is returned; otherwise, an error of type
`mold-collision' is signaled."
  (check-type from-mold mold)
  (check-type property-name property-name)
  (check-type to-mold mold)
  (assert (null (set-difference (mold-properties from-mold)
                                (mold-properties to-mold))) ()
          "~A does not contain all the properties of ~A, and is thus not a ~
           valid transition to it." to-mold from-mold)
  (assert (equal (list property-name)
                 (set-difference (mold-properties to-mold)
                                 (mold-properties from-mold)))
          () "~A is not a unique property transition from ~A to ~A."
          property-name from-mold to-mold)
  (awhen (find property-name (mold-transitions from-mold) :key 'car)
    (error 'mold-collision :new-mold to-mold :collision-mold (cdr it)))
  (aconsf (mold-transitions from-mold) property-name to-mold)
  from-mold)

(defun find-mold-by-transition (start-mold goal-properties)
  "Searches the transition tree from START-MOLD to find the mold containing
GOAL-PROPERTIES, returning that mold if found, or NIL on failure."
  (check-type start-mold mold)
  (check-list-type goal-properties property-name)
  ;; This algorithm is very concise, but it's not optimal AND it's unclear.
  ;; Probably the first target for cleaning up. - Adlai
  (let ((path (set-difference goal-properties (mold-properties start-mold))))
    (if (null path) start-mold
        (awhen (some (fun (find-transition start-mold _)) path)
          (find-mold-by-transition it path)))))

(defvar *maps* (make-hash-table :test 'equal))

(defun tree-find-if (test tree &key (key #'identity))
  (cond ((null tree) nil)
        ((atom tree)
         (when (funcall test (funcall key tree))
           tree))
        (t (or (tree-find-if test (car tree) :key key)
               (tree-find-if test (cdr tree) :key key)))))

(defun find-map (parents properties)
  (tree-find-if (lambda (map) (equal properties (map-properties map)))
                (gethash parents *maps*)))

(defun make-object (parents properties)
  (let ((maybe-map (find-map parents properties)))
    (if (and maybe-map 
             (every #'eq properties (map-properties maybe-map)))
        (%make-object :map maybe-map
                      :property-values (make-array (length (map-properties map))))
        (%make-object :map (make-map :parents parents 
                                     :properties properties)
                      :property-values (make-array (length properties))))))
