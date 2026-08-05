;;;; sampling.lisp
;;;; Poisson disc sampling (Bridson's algorithm), ported to use our seeded RNG

(in-package #:cl-procgen)

(defstruct (%poisson-grid (:constructor %make-poisson-grid))
  (cells (make-array 0) :type simple-vector)
  (cols 0 :type fixnum)
  (rows 0 :type fixnum)
  (cell-size 1.0 :type single-float))

(defun %poisson-grid-init (width height cell-size)
  (let* ((cols (max 1 (ceiling width cell-size)))
         (rows (max 1 (ceiling height cell-size))))
    (%make-poisson-grid :cells (make-array (* cols rows) :initial-element nil)
                         :cols cols :rows rows :cell-size cell-size)))

(defun %poisson-grid-set (grid x y idx)
  (let ((col (floor x (%poisson-grid-cell-size grid)))
        (row (floor y (%poisson-grid-cell-size grid))))
    (when (and (>= col 0) (< col (%poisson-grid-cols grid))
               (>= row 0) (< row (%poisson-grid-rows grid)))
      (setf (aref (%poisson-grid-cells grid) (+ (* row (%poisson-grid-cols grid)) col)) idx))))

(defun %poisson-grid-far-enough-p (grid all-points px py min-dist-sq)
  (let* ((cell-size (%poisson-grid-cell-size grid))
         (col (floor px cell-size))
         (row (floor py cell-size))
         (search 2))
    (loop for dy from (- search) to search
          always (loop for dx from (- search) to search
                       for c = (+ col dx)
                       for r = (+ row dy)
                       always (or (< c 0) (>= c (%poisson-grid-cols grid))
                                  (< r 0) (>= r (%poisson-grid-rows grid))
                                  (let ((idx (aref (%poisson-grid-cells grid)
                                                   (+ (* r (%poisson-grid-cols grid)) c))))
                                    (or (null idx)
                                        (let* ((other (aref all-points idx))
                                               (ox (aref other 0)) (oy (aref other 1))
                                               (ddx (- px ox)) (ddy (- py oy)))
                                          (>= (+ (* ddx ddx) (* ddy ddy)) min-dist-sq)))))))))

(defun map-poisson-disc (fn width height min-dist
                          &key rng (max-attempts 30) predicate)
  "Generate Poisson disc samples over [0,WIDTH) x [0,HEIGHT) with minimum
   separation MIN-DIST (Bridson's algorithm), calling FN with (x y) for each
   accepted point. Does not allocate a result vector -- use
   POISSON-DISC-SAMPLE if you want the points collected.

   RNG defaults to a freshly-seeded (make-rng). MAX-ATTEMPTS bounds how many
   candidate points are tried around each active point before it is retired.
   PREDICATE, if given, is called as (PREDICATE x y) and must return true for
   a candidate point to be accepted."
  (let* ((rng (or rng (make-rng)))
         (width (sf width)) (height (sf height)) (min-dist (sf min-dist))
         (cell-size (/ min-dist (sqrt 2.0)))
         (min-dist-sq (* min-dist min-dist))
         (grid (%poisson-grid-init width height cell-size))
         (all-points (make-array 64 :adjustable t :fill-pointer 0))
         (active (make-array 64 :adjustable t :fill-pointer 0)))
    (flet ((try-add (x y)
             (when (and (>= x 0.0) (< x width) (>= y 0.0) (< y height)
                        (%poisson-grid-far-enough-p grid all-points x y min-dist-sq)
                        (or (null predicate) (funcall predicate x y)))
               (let ((idx (fill-pointer all-points)))
                 (vector-push-extend (vector x y) all-points)
                 (%poisson-grid-set grid x y idx)
                 (vector-push-extend idx active)
                 t))))
      (let ((initial-x (/ width 2.0)) (initial-y (/ height 2.0)))
        (try-add initial-x initial-y))
      (loop while (plusp (fill-pointer active))
            do (let* ((i (rng-int rng 0 (1- (fill-pointer active))))
                      (base-idx (aref active i))
                      (base (aref all-points base-idx))
                      (bx (aref base 0)) (by (aref base 1))
                      (found nil))
                 (dotimes (attempt max-attempts)
                   (let* ((angle (* (rng-float rng) +tau+))
                          (radius (+ min-dist (* (rng-float rng) min-dist)))
                          (cx (+ bx (* (cos angle) radius)))
                          (cy (+ by (* (sin angle) radius))))
                     (when (try-add cx cy) (setf found t))))
                 (unless found
                   (setf (aref active i) (aref active (1- (fill-pointer active))))
                   (decf (fill-pointer active))))))
    (loop for i below (fill-pointer all-points)
          do (let ((p (aref all-points i))) (funcall fn (aref p 0) (aref p 1))))))

(defun poisson-disc-sample (width height min-dist &key rng (max-attempts 30) predicate)
  "Generate Poisson disc samples over [0,WIDTH) x [0,HEIGHT) with minimum
   separation MIN-DIST. Returns a (simple-array T (*)) of 2-element
   single-float vectors #(x y). See MAP-POISSON-DISC for keyword meanings."
  (let ((result (make-array 0 :adjustable t :fill-pointer 0)))
    (map-poisson-disc (lambda (x y) (vector-push-extend (vector x y) result))
                       width height min-dist
                       :rng rng :max-attempts max-attempts :predicate predicate)
    (coerce result 'simple-vector)))
