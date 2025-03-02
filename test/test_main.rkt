#lang racket

(require rackunit
         "../src/logic.rkt")

(module+ test
  (check-true (valid-score? 1))
  (check-true (valid-score? 10))
  (check-false (valid-score? 0))
  (check-false (valid-score? 11))
  (check-true (compute-flagged 3 4 7))
  (check-true (compute-flagged 6 9 7))
  (check-true (compute-flagged 6 5 2))
  (check-false (compute-flagged 6 5 7)))
