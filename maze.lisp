;;;; maze.lisp
;;;; Maze generation via randomized depth-first-search (recursive backtracker)

(in-package #:cl-procgen)

(defconstant +maze-north+ 1)
(defconstant +maze-east+  2)
(defconstant +maze-south+ 4)
(defconstant +maze-west+  8)

(defparameter %maze-dirs
  (vector (list +maze-north+ 0 -1 +maze-south+)
          (list +maze-east+  1  0 +maze-west+)
          (list +maze-south+ 0  1 +maze-north+)
          (list +maze-west+ -1  0 +maze-east+))
  "Each entry is (WALL-BIT DX DY OPPOSITE-BIT) for one cardinal direction.")

(defun %maze-carve-flags (rng width height)
  "Run a randomized recursive-backtracker DFS over a WIDTH x HEIGHT cell grid,
   returning a (HEIGHT WIDTH) array of per-cell wall bitflags (bit0=N, bit1=E,
   bit2=S, bit3=W; a set bit means a wall is present on that side). Uses an
   explicit stack rather than recursion to avoid deep call stacks on large
   mazes."
  (let ((flags (make-array (list height width)
                            :element-type '(unsigned-byte 8)
                            :initial-element (logior +maze-north+ +maze-east+
                                                      +maze-south+ +maze-west+)))
        (visited (make-array (list height width) :element-type 'bit :initial-element 0))
        (stack (make-array 64 :adjustable t :fill-pointer 0)))
    (vector-push-extend (cons 0 0) stack)
    (setf (aref visited 0 0) 1)
    (loop while (plusp (fill-pointer stack))
          do (let* ((top (aref stack (1- (fill-pointer stack))))
                     (cx (car top)) (cy (cdr top))
                     (dirs (rng-shuffle rng (copy-seq %maze-dirs)))
                     (advanced nil))
                (loop for dir across dirs
                      do (destructuring-bind (wall dx dy opposite) dir
                           (let ((nx (+ cx dx)) (ny (+ cy dy)))
                             (when (and (>= nx 0) (< nx width) (>= ny 0) (< ny height)
                                        (zerop (aref visited ny nx)))
                               (setf (aref flags cy cx) (logandc2 (aref flags cy cx) wall))
                               (setf (aref flags ny nx) (logandc2 (aref flags ny nx) opposite))
                               (setf (aref visited ny nx) 1)
                               (vector-push-extend (cons nx ny) stack)
                               (setf advanced t)
                               (return)))))
                (unless advanced
                  (decf (fill-pointer stack)))))
    flags))

(defun maze-flags->grid (flags)
  "Convert a (HEIGHT WIDTH) per-cell wall-bitflag array (as produced by MAZE
   with :FORMAT :FLAGS) into a (2*HEIGHT+1) x (2*WIDTH+1) bit grid indexed as
   (AREF grid y x), where 1 means wall and 0 means passage. Cell (CY, CX) of
   the flag grid occupies passage cell (2*CY+1, 2*CX+1) of the returned grid."
  (destructuring-bind (height width) (array-dimensions flags)
    (let ((grid (make-array (list (1+ (* 2 height)) (1+ (* 2 width)))
                             :element-type 'bit :initial-element 1)))
      (dotimes (cy height)
        (dotimes (cx width)
          (let ((gx (1+ (* 2 cx))) (gy (1+ (* 2 cy)))
                (f (aref flags cy cx)))
            (setf (aref grid gy gx) 0)
            (when (zerop (logand f +maze-north+)) (setf (aref grid (1- gy) gx) 0))
            (when (zerop (logand f +maze-east+))  (setf (aref grid gy (1+ gx)) 0))
            (when (zerop (logand f +maze-south+)) (setf (aref grid (1+ gy) gx) 0))
            (when (zerop (logand f +maze-west+))  (setf (aref grid gy (1- gx)) 0)))))
      grid)))

(defun maze (rng width height &key (format :walls))
  "Generate a WIDTH x HEIGHT maze via a randomized recursive-backtracker DFS,
   guaranteeing every cell is reachable from every other (a perfect maze, one
   unique path between any two cells).

   FORMAT selects the return representation:
   - :FLAGS returns the raw (HEIGHT WIDTH) array of per-cell wall bitflags
     (bit0=N, bit1=E, bit2=S, bit3=W; set means walled).
   - :WALLS (default) returns a (2*HEIGHT+1) x (2*WIDTH+1) bit grid indexed
     (AREF grid y x), 1 = wall / 0 = passage, matching the convention used by
     CELLULAR-AUTOMATA and DRUNKARDS-WALK. See MAZE-FLAGS->GRID for the exact
     cell-to-grid-coordinate mapping."
  (let ((flags (%maze-carve-flags rng width height)))
    (ecase format
      (:flags flags)
      (:walls (maze-flags->grid flags)))))
