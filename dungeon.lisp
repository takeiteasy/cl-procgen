;;;; dungeon.lisp
;;;; BSP room-and-corridor dungeon generation

(in-package #:common-generation)

(defstruct (dungeon-room (:constructor %make-room (x y w h)))
  "A rectangular room placed by BSP-DUNGEON, in grid cell coordinates. X and Y
   are the top-left corner; W and H are the width and height."
  (x 0 :type fixnum) (y 0 :type fixnum) (w 0 :type fixnum) (h 0 :type fixnum))

(defun %room-center (r)
  (values (+ (dungeon-room-x r) (floor (dungeon-room-w r) 2))
          (+ (dungeon-room-y r) (floor (dungeon-room-h r) 2))))

(defstruct (%bsp-leaf (:constructor %make-bsp-leaf (x y w h)))
  (x 0 :type fixnum) (y 0 :type fixnum) (w 0 :type fixnum) (h 0 :type fixnum)
  left right room)

(defun %bsp-split (rng leaf min-leaf max-leaf depth max-depth)
  "Recursively split LEAF into two children when it is large enough and DEPTH
   allows, alternating split axis by whichever dimension is larger."
  (when (< depth max-depth)
    (let* ((w (%bsp-leaf-w leaf)) (h (%bsp-leaf-h leaf))
           (split-horizontal (if (= w h) (zerop (rng-int rng 0 1)) (< w h))))
      (when (or (> w max-leaf) (> h max-leaf)
                (< (rng-float rng) 0.35))
        (if split-horizontal
            (when (>= h (* 2 min-leaf))
              (let ((split (rng-int rng min-leaf (- h min-leaf))))
                (setf (%bsp-leaf-left leaf)
                      (%make-bsp-leaf (%bsp-leaf-x leaf) (%bsp-leaf-y leaf) w split))
                (setf (%bsp-leaf-right leaf)
                      (%make-bsp-leaf (%bsp-leaf-x leaf) (+ (%bsp-leaf-y leaf) split)
                                       w (- h split)))))
            (when (>= w (* 2 min-leaf))
              (let ((split (rng-int rng min-leaf (- w min-leaf))))
                (setf (%bsp-leaf-left leaf)
                      (%make-bsp-leaf (%bsp-leaf-x leaf) (%bsp-leaf-y leaf) split h))
                (setf (%bsp-leaf-right leaf)
                      (%make-bsp-leaf (+ (%bsp-leaf-x leaf) split) (%bsp-leaf-y leaf)
                                       (- w split) h)))))
        (when (%bsp-leaf-left leaf)
          (%bsp-split rng (%bsp-leaf-left leaf) min-leaf max-leaf (1+ depth) max-depth)
          (%bsp-split rng (%bsp-leaf-right leaf) min-leaf max-leaf (1+ depth) max-depth))))))

(defun %bsp-make-rooms (rng leaf min-room room-margin rooms)
  "Depth-first walk of the BSP tree: carve one room in each leaf that was not
   further split, and recurse into children. Collects rooms into ROOMS."
  (if (%bsp-leaf-left leaf)
      (progn (%bsp-make-rooms rng (%bsp-leaf-left leaf) min-room room-margin rooms)
             (%bsp-make-rooms rng (%bsp-leaf-right leaf) min-room room-margin rooms))
      (let* ((avail-w (- (%bsp-leaf-w leaf) (* 2 room-margin)))
             (avail-h (- (%bsp-leaf-h leaf) (* 2 room-margin))))
        (when (and (>= avail-w min-room) (>= avail-h min-room))
          (let* ((rw (rng-int rng min-room avail-w))
                 (rh (rng-int rng min-room avail-h))
                 (rx (+ (%bsp-leaf-x leaf) room-margin
                        (rng-int rng 0 (- avail-w rw))))
                 (ry (+ (%bsp-leaf-y leaf) room-margin
                        (rng-int rng 0 (- avail-h rh))))
                 (room (%make-room rx ry rw rh)))
            (setf (%bsp-leaf-room leaf) room)
            (vector-push-extend room rooms))))))

(defun %bsp-any-room (leaf)
  "Find any single room within LEAF's subtree, or NIL if it carved none."
  (or (%bsp-leaf-room leaf)
      (and (%bsp-leaf-left leaf)
           (or (%bsp-any-room (%bsp-leaf-left leaf))
               (%bsp-any-room (%bsp-leaf-right leaf))))))

(defun %carve-rect (grid x0 y0 x1 y1 width height)
  (loop for y from (max 0 y0) to (min (1- height) y1)
        do (loop for x from (max 0 x0) to (min (1- width) x1)
                 do (setf (aref grid y x) 0))))

(defun %bsp-connect (rng grid leaf width height)
  "Recursively connect the rooms of LEAF's two children with an L-shaped
   corridor between a representative room in each, then recurse."
  (when (%bsp-leaf-left leaf)
    (let ((left (%bsp-leaf-left leaf)) (right (%bsp-leaf-right leaf)))
      (%bsp-connect rng grid left width height)
      (%bsp-connect rng grid right width height)
      (let ((ra (%bsp-any-room left)) (rb (%bsp-any-room right)))
        (when (and ra rb)
          (multiple-value-bind (ax ay) (%room-center ra)
            (multiple-value-bind (bx by) (%room-center rb)
              (if (zerop (rng-int rng 0 1))
                  (progn (%carve-rect grid (min ax bx) ay (max ax bx) ay width height)
                         (%carve-rect grid bx (min ay by) bx (max ay by) width height))
                  (progn (%carve-rect grid ax (min ay by) ax (max ay by) width height)
                         (%carve-rect grid (min ax bx) by (max ax bx) by width height))))))))))

(defun bsp-dungeon (rng width height
                     &key (min-leaf 8) (max-leaf 20)
                          (min-room 4) (room-margin 1) (max-depth 6))
  "Generate a room-and-corridor dungeon over a WIDTH x HEIGHT grid using
   binary space partitioning: the area is recursively split into leaves
   (MIN-LEAF/MAX-LEAF bound each leaf's side length, MAX-DEPTH bounds
   recursion), one room is carved per leaf (at least MIN-ROOM cells per side,
   inset by ROOM-MARGIN from the leaf's edges), and sibling subtrees are
   joined by L-shaped corridors between representative rooms.

   Returns two values: a (HEIGHT WIDTH) bit array indexed (AREF grid y x)
   where 1 means wall and 0 means floor, and a SIMPLE-VECTOR of DUNGEON-ROOM
   structs describing every carved room (for downstream entity placement or
   connectivity checks)."
  (let* ((grid (make-array (list height width) :element-type 'bit :initial-element 1))
         (root (%make-bsp-leaf 0 0 width height))
         (rooms (make-array 8 :adjustable t :fill-pointer 0)))
    (%bsp-split rng root min-leaf max-leaf 0 max-depth)
    (%bsp-make-rooms rng root min-room room-margin rooms)
    (loop for r across rooms
          do (%carve-rect grid (dungeon-room-x r) (dungeon-room-y r)
                           (1- (+ (dungeon-room-x r) (dungeon-room-w r)))
                           (1- (+ (dungeon-room-y r) (dungeon-room-h r)))
                           width height))
    (%bsp-connect rng grid root width height)
    (values grid (coerce rooms 'simple-vector))))
