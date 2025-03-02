#lang racket

(provide compute-flagged valid-score?)

(define (valid-score? n)
  (and (integer? n) (<= 1 n 10)))

(define (compute-flagged mood stress engagement)
  (or (<= mood 3)
      (>= stress 8)
      (<= engagement 3)))
