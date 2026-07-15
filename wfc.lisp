;;;; wfc.lisp
;;;; Wave Function Collapse (overlapping model) grid generation

(in-package #:common-generation)

;;; The solver core (wave / entropy / observe / propagate / contradiction)
;;; operates purely on patterns + weights + adjacency; this file's job is to
;;; derive those three from a sample grid via NxN pattern extraction (the
;;; "overlapping" model). A future tiled/authored-rules front-end could feed
;;; the same core (see TICKETS.md).

(declaim (inline %wfc-direction))
(defun %wfc-direction (d)
  "Return (VALUES DY DX), the row/column offset for propagation direction
   index D: 0 = up, 1 = down, 2 = left, 3 = right."
  (case d
    (0 (values -1 0))
    (1 (values 1 0))
    (2 (values 0 -1))
    (t (values 0 1))))

(defun %wfc-extract-pattern (sample sy sx n height width periodic-input)
  "Extract the N x N block of SAMPLE whose top-left corner is (SY, SX),
   wrapping coordinates modulo HEIGHT/WIDTH when PERIODIC-INPUT is true."
  (let ((pat (make-array (list n n) :element-type (array-element-type sample))))
    (dotimes (dy n)
      (dotimes (dx n)
        (let ((yy (+ sy dy)) (xx (+ sx dx)))
          (when periodic-input
            (setf yy (mod yy height) xx (mod xx width)))
          (setf (aref pat dy dx) (aref sample yy xx)))))
    pat))

(defun %wfc-extract-patterns (sample n periodic-input)
  "Slide an N x N window over SAMPLE (wrapping when PERIODIC-INPUT is true)
   and collect the distinct patterns found, in first-seen order. Returns two
   values: a SIMPLE-VECTOR of N x N pattern arrays, and a parallel
   SIMPLE-ARRAY of SINGLE-FLOAT occurrence-count weights."
  (destructuring-bind (height width) (array-dimensions sample)
    (let ((table (make-hash-table :test 'equalp))
          (order '())
          (sy-max (if periodic-input height (1+ (- height n))))
          (sx-max (if periodic-input width (1+ (- width n)))))
      (dotimes (sy sy-max)
        (dotimes (sx sx-max)
          (let* ((pat (%wfc-extract-pattern sample sy sx n height width periodic-input))
                 (entry (gethash pat table)))
            (if entry
                (incf (car entry))
                (progn (setf (gethash pat table) (cons 1 pat))
                       (push pat order))))))
      (setf order (nreverse order))
      (let* ((p (length order))
             (patterns (make-array p))
             (weights (make-array p :element-type 'single-float)))
        (loop for i from 0
              for pat in order
              do (setf (aref patterns i) pat
                       (aref weights i) (sf (car (gethash pat table)))))
        (values patterns weights)))))

(defun %wfc-compatible-p (a b dy dx n)
  "True if N x N pattern B may be placed as A's neighbor at offset (DY, DX):
   the region where A and B overlap (N minus the offset's rows/columns) must
   agree exactly."
  (dotimes (y n t)
    (dotimes (x n)
      (let ((by (- y dy)) (bx (- x dx)))
        (when (and (>= by 0) (< by n) (>= bx 0) (< bx n))
          (unless (eql (aref a y x) (aref b by bx))
            (return-from %wfc-compatible-p nil)))))))

(defun %wfc-build-adjacency (patterns n)
  "Precompute, for each of the 4 directions and each pattern index I, the
   BIT-VECTOR of pattern indices J that may legally sit at that offset from
   I. Returns a length-4 SIMPLE-VECTOR of SIMPLE-VECTORs of
   SIMPLE-BIT-VECTORs, indexed [direction][i] -> bits over j."
  (let* ((p (length patterns))
         (adjacency (make-array 4)))
    (dotimes (d 4)
      (multiple-value-bind (dy dx) (%wfc-direction d)
        (let ((dir-adj (make-array p)))
          (dotimes (i p)
            (let ((bits (make-array p :element-type 'bit :initial-element 0)))
              (dotimes (j p)
                (when (%wfc-compatible-p (aref patterns i) (aref patterns j) dy dx n)
                  (setf (aref bits j) 1)))
              (setf (aref dir-adj i) bits)))
          (setf (aref adjacency d) dir-adj))))
    adjacency))

(defun %wfc-min-entropy-cell (rng wave counts sum-w sum-wlogw height width)
  "Find the uncollapsed (COUNT > 1) cell of lowest Shannon entropy over its
   remaining patterns' weights, breaking ties with a small random jitter so
   collapse order isn't always raster-first. WAVE is unused directly (kept
   for signature symmetry with the other solver steps) but COUNTS/SUM-W/
   SUM-WLOGW carry the per-cell state. Returns (VALUES Y X), or NIL if every
   cell is already collapsed."
  (declare (ignore wave))
  (let ((best-y nil) (best-x nil) (best-e most-positive-double-float))
    (dotimes (y height)
      (dotimes (x width)
        (when (> (aref counts y x) 1)
          (let* ((sw (aref sum-w y x))
                 (entropy (- (log sw) (/ (aref sum-wlogw y x) sw)))
                 (e (+ entropy (* 1.0d-6 (coerce (rng-float rng) 'double-float)))))
            (when (< e best-e)
              (setf best-e e best-y y best-x x))))))
    (if best-y (values best-y best-x) (values nil nil))))

(defun %wfc-observe (rng wave counts sum-w sum-wlogw weights wlogw y x p)
  "Collapse cell (Y, X) of WAVE to a single pattern, chosen randomly weighted
   by pattern frequency among the patterns still allowed there. Updates
   COUNTS/SUM-W/SUM-WLOGW for the cell in place."
  (let ((allowed (make-array (aref counts y x) :fill-pointer 0)))
    (dotimes (j p)
      (when (= 1 (aref wave y x j))
        (vector-push j allowed)))
    (let* ((idx (rng-weighted-choice rng allowed :key (lambda (j) (aref weights j))))
           (chosen (aref allowed idx)))
      (dotimes (j p)
        (when (and (/= j chosen) (= 1 (aref wave y x j)))
          (setf (aref wave y x j) 0)))
      (setf (aref counts y x) 1
            (aref sum-w y x) (coerce (aref weights chosen) 'double-float)
            (aref sum-wlogw y x) (aref wlogw chosen))
      chosen)))

(defun %wfc-pattern-supported-p (wave y x adjacency-d p j)
  "True if some pattern still allowed at cell (Y, X) of WAVE permits pattern
   J as its neighbor in the direction ADJACENCY-D (one of the 4 per-
   direction vectors from %WFC-BUILD-ADJACENCY) was built for."
  (dotimes (i p nil)
    (when (and (= 1 (aref wave y x i)) (= 1 (aref (aref adjacency-d i) j)))
      (return t))))

(defun %wfc-propagate (wave counts sum-w sum-wlogw weights wlogw adjacency
                        width height p periodic-output start-y start-x)
  "Enforce adjacency constraints outward from cell (START-Y, START-X) via a
   worklist until it empties or some cell's possibility set is driven to
   zero. Returns NIL on contradiction, T otherwise.

   NOTE: %WFC-PATTERN-SUPPORTED-P rechecks support with a full O(P) scan on
   every candidate removal, so this is O(P^2) worst case per propagated
   cell. A per-cell-per-direction support-count matrix (as in the reference
   WFC implementations) would make each removal amortized O(1); left as a
   follow-up optimization since P stays small for typical sample sizes (see
   TICKETS.md)."
  (let ((stack (list (cons start-y start-x))))
    (loop while stack
          do (let* ((cell (pop stack))
                    (cy (car cell)) (cx (cdr cell)))
               (dotimes (d 4)
                 (multiple-value-bind (dy dx) (%wfc-direction d)
                   (let ((ny (+ cy dy)) (nx (+ cx dx)))
                     (when periodic-output
                       (setf ny (mod ny height) nx (mod nx width)))
                     (when (and (>= ny 0) (< ny height) (>= nx 0) (< nx width))
                       (let ((changed nil)
                             (adjacency-d (aref adjacency d)))
                         (dotimes (j p)
                           (when (and (= 1 (aref wave ny nx j))
                                      (not (%wfc-pattern-supported-p wave cy cx adjacency-d p j)))
                             (setf (aref wave ny nx j) 0)
                             (decf (aref counts ny nx))
                             (decf (aref sum-w ny nx) (coerce (aref weights j) 'double-float))
                             (decf (aref sum-wlogw ny nx) (aref wlogw j))
                             (setf changed t)
                             (when (<= (aref counts ny nx) 0)
                               (return-from %wfc-propagate nil))))
                         (when changed (push (cons ny nx) stack)))))))))
    t))

(defun %wfc-run-once (rng weights wlogw adjacency height width p
                       total-w total-wlogw periodic-output)
  "Attempt one full collapse of a HEIGHT x WIDTH wave over P patterns (with
   WEIGHTS/WLOGW/ADJACENCY as built by %WFC-EXTRACT-PATTERNS/%WFC-BUILD-
   ADJACENCY). Returns (VALUES WAVE T) on success, or (VALUES NIL NIL) on
   contradiction."
  (let ((wave (make-array (list height width p) :element-type 'bit :initial-element 1))
        (counts (make-array (list height width) :element-type 'fixnum :initial-element p))
        (sum-w (make-array (list height width) :element-type 'double-float :initial-element total-w))
        (sum-wlogw (make-array (list height width) :element-type 'double-float
                                :initial-element total-wlogw)))
    (loop
      (multiple-value-bind (y x) (%wfc-min-entropy-cell rng wave counts sum-w sum-wlogw height width)
        (unless y (return (values wave t)))
        (%wfc-observe rng wave counts sum-w sum-wlogw weights wlogw y x p)
        (unless (%wfc-propagate wave counts sum-w sum-wlogw weights wlogw adjacency
                                 width height p periodic-output y x)
          (return (values nil nil)))))))

(defun %wfc-readout (wave patterns p height width element-type)
  "Assemble the final HEIGHT x WIDTH output array from a fully-collapsed
   WAVE: each cell's value is the top-left cell of its one remaining
   pattern."
  (let ((out (make-array (list height width) :element-type element-type)))
    (dotimes (y height)
      (dotimes (x width)
        (dotimes (j p)
          (when (= 1 (aref wave y x j))
            (setf (aref out y x) (aref (aref patterns j) 0 0))
            (return)))))
    out))

(defun wave-function-collapse (rng sample out-width out-height
                                &key (n 3) (periodic-input t) (periodic-output nil)
                                     (symmetry :none) (max-retries 20))
  "Generate an OUT-WIDTH x OUT-HEIGHT grid that is locally similar to SAMPLE
   using the overlapping Wave Function Collapse algorithm: N x N patterns
   (and their frequencies) are learned from SAMPLE, an output wave the same
   size as the result is constrained by direct-overlap adjacency between
   patterns, and the lowest-entropy cell is repeatedly collapsed and its
   choice propagated outward until every cell holds exactly one pattern.

   SAMPLE is a 2D array of tile values (any element type comparable with
   EQL, e.g. BIT or FIXNUM) — distinct values are distinct tiles, so the
   bit-grid output of e.g. CELLULAR-AUTOMATA can be used directly. N is the
   pattern window size and must not exceed SAMPLE's dimensions.
   PERIODIC-INPUT (T by default) wraps the pattern-extraction window around
   SAMPLE's edges. PERIODIC-OUTPUT (NIL by default) wraps constraint
   propagation around the output grid's edges. SYMMETRY only accepts :NONE
   for now — reflected/rotated pattern variants are not yet implemented
   (see TICKETS.md).

   On a contradiction the whole wave is discarded and retried, drawing
   further random numbers from the same RNG (it is never reseeded, so the
   overall result stays reproducible from RNG's initial seed). MAX-RETRIES
   bounds the number of attempts.

   Returns a fresh (OUT-HEIGHT OUT-WIDTH) array with the same element-type
   as SAMPLE, indexed (AREF result y x), or NIL if no attempt found a
   contradiction-free solution within MAX-RETRIES tries."
  (unless (eq symmetry :none)
    (error "WAVE-FUNCTION-COLLAPSE: SYMMETRY ~S is not yet implemented (only :NONE is supported); see TICKETS.md."
           symmetry))
  (destructuring-bind (sh sw) (array-dimensions sample)
    (assert (and (<= n sh) (<= n sw)) (n)
            "N (~D) must not exceed SAMPLE's dimensions (~D x ~D)." n sh sw)
    (multiple-value-bind (patterns weights) (%wfc-extract-patterns sample n periodic-input)
      (let* ((p (length patterns))
             (wlogw (make-array p :element-type 'double-float))
             (total-w 0.0d0)
             (total-wlogw 0.0d0))
        (dotimes (i p)
          (let ((w (coerce (aref weights i) 'double-float)))
            (setf (aref wlogw i) (* w (log w)))
            (incf total-w w)
            (incf total-wlogw (aref wlogw i))))
        (let ((adjacency (%wfc-build-adjacency patterns n)))
          (dotimes (attempt max-retries nil)
            (declare (ignorable attempt))
            (multiple-value-bind (wave ok)
                (%wfc-run-once rng weights wlogw adjacency
                               out-height out-width p total-w total-wlogw periodic-output)
              (when ok
                (return (%wfc-readout wave patterns p out-height out-width
                                       (array-element-type sample)))))))))))
