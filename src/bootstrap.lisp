;; This file is part of Sheeple

;; bootstrap.lisp
;;
;; This creates all the base objects that will be used during cloning.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

(setf (find-proto 't)
      (let ((sheep (allocate-sheep)))
        (setf (sheep-nickname sheep) 't)
        sheep))

(setf (find-proto 'dolly)
  (let ((sheep (allocate-sheep)))
    (setf (sheep-nickname sheep) 'dolly)
    (add-parent t sheep)
    sheep))

(defmessage initialize-sheep (sheep &key))
(defreply initialize-sheep (sheep
                            &key 
                            nickname
                            documentation)
  (setf (sheep-nickname sheep) nickname)
  (when documentation
    (setf (sheep-documentation sheep) documentation))
  sheep)

(defmessage reinitialize-sheep (sheep &key))
(defreply reinitialize-sheep (sheep
                              &key new-parents
                              documentation)
  ;; CLOBBER TIME
  (loop for parent in (sheep-direct-parents sheep)
     do (remove-parent parent sheep))
  (remove-all-direct-properties sheep)
  ;; MOAR PARENTS
  (add-parents (if new-parents (sheepify-list new-parents) (list #@dolly))
               sheep)
  ;; DOX PLOX
  (when documentation
    (setf (sheep-documentation sheep) documentation))
  sheep)

(defproto dolly (t) ())

;;; Boxed built-ins
(defproto boxed-object (t) ())
(defproto symbol (#@boxed-object) ())
(defproto sequence (#@boxed-object) ())
(defproto array (#@boxed-object) ())
(defproto number (#@boxed-object) ())
(defproto character (#@boxed-object) ())
(defproto function (#@boxed-object) ())
(defproto hash-table (#@boxed-object) ())
(defproto package (#@boxed-object) ())
(defproto pathname (#@boxed-object) ())
(defproto readtable (#@boxed-object) ())
(defproto stream (#@boxed-object) ())
(defproto list (#@sequence) ())
(defproto null (#@symbol #@list) ())
(defproto cons (#@list) ())
(defproto vector (#@array #@sequence) ())
(defproto bit-vector (#@vector) ())
(defproto string (#@vector) ())
(defproto complex (#@number) ())
(defproto integer (#@number) ())
(defproto float (#@number) ())
