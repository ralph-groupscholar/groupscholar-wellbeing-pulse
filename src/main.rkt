#lang racket

(require racket/cmdline
         racket/string
         "db.rkt"
         "logic.rkt")

(define (usage)
  (displayln "gs-wellbeing-pulse commands:")
  (displayln "  init-db")
  (displayln "  seed-db")
  (displayln "  add-cohort --name NAME --start YYYY-MM-DD")
  (displayln "  add-scholar --name NAME --cohort COHORT --status STATUS --risk-level LEVEL")
  (displayln "  list-cohorts")
  (displayln "  list-scholars [--cohort COHORT]")
  (displayln "  log-checkin --scholar-id ID --date YYYY-MM-DD --mood N --stress N --engagement N --notes TEXT [--flagged true|false] [--tags tag1,tag2]")
  (displayln "  list-checkins [--scholar-id ID] [--cohort COHORT] [--limit N]")
  (displayln "  weekly-summary --week-start YYYY-MM-DD [--cohort COHORT]")
  (displayln "Environment variables: DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DB_SSLMODE")
  (exit 1))

(define (parse-int value label)
  (define parsed (string->number value))
  (unless (and parsed (integer? parsed))
    (raise-user-error 'input (format "~a must be an integer" label)))
  parsed)

(define (parse-score value label)
  (define parsed (parse-int value label))
  (unless (valid-score? parsed)
    (raise-user-error 'input (format "~a must be between 1 and 10" label)))
  parsed)

(define (parse-bool value)
  (define normalized (string-downcase value))
  (cond
    [(member normalized '("true" "t" "yes" "y" "1")) #t]
    [(member normalized '("false" "f" "no" "n" "0")) #f]
    [else (raise-user-error 'input "flagged must be true or false")]))

(define (parse-tags value)
  (define tags (filter (lambda (s) (not (string=? s "")))
                       (map string-trim (string-split value ","))))
  (if (null? tags) #f tags))

(define (print-rows headers rows)
  (displayln (string-join headers " | "))
  (displayln (make-string (string-length (string-join headers " | ")) #\-))
  (for ([row rows])
    (define values (for/list ([i (in-range (vector-length row))])
                     (format "~a" (vector-ref row i))))
    (displayln (string-join values " | "))))

(define (run-with-args args thunk)
  (parameterize ([current-command-line-arguments (list->vector args)])
    (thunk)))

(define args (vector->list (current-command-line-arguments)))
(define cmd (if (null? args) #f (car args)))
(define rest (if (null? args) '() (cdr args)))

(define (require-arg value label)
  (unless value
    (raise-user-error 'input (format "Missing required argument: ~a" label))))

(define (handle-init-db)
  (with-connection
   (lambda (conn)
     (init-db! conn)
     (displayln "Database initialized."))))

(define (handle-seed-db)
  (with-connection
   (lambda (conn)
     (seed-db! conn)
     (displayln "Seed data inserted."))))

(define (handle-add-cohort)
  (define name #f)
  (define start-date #f)
  (run-with-args
   rest
   (lambda ()
     (command-line
      #:program "gs-wellbeing-pulse add-cohort"
      #:once-each
      ["--name" value "Cohort name" (set! name value)]
      ["--start" value "Start date" (set! start-date value)])))
  (require-arg name "--name")
  (require-arg start-date "--start")
  (with-connection
   (lambda (conn)
     (define row (add-cohort! conn name start-date))
     (displayln (format "Added cohort with id ~a" (vector-ref row 0))))))

(define (handle-add-scholar)
  (define name #f)
  (define cohort #f)
  (define status "active")
  (define risk-level "medium")
  (run-with-args
   rest
   (lambda ()
     (command-line
      #:program "gs-wellbeing-pulse add-scholar"
      #:once-each
      ["--name" value "Scholar name" (set! name value)]
      ["--cohort" value "Cohort name" (set! cohort value)]
      ["--status" value "Status" (set! status value)]
      ["--risk-level" value "Risk level" (set! risk-level value)])))
  (require-arg name "--name")
  (require-arg cohort "--cohort")
  (with-connection
   (lambda (conn)
     (define row (add-scholar! conn name cohort status risk-level))
     (displayln (format "Added scholar with id ~a" (vector-ref row 0))))))

(define (handle-list-cohorts)
  (with-connection
   (lambda (conn)
     (define rows (list-cohorts conn))
     (print-rows '("ID" "Cohort" "Start") rows))))

(define (handle-list-scholars)
  (define cohort #f)
  (run-with-args
   rest
   (lambda ()
     (command-line
      #:program "gs-wellbeing-pulse list-scholars"
      #:once-each
      ["--cohort" value "Filter by cohort" (set! cohort value)])))
  (with-connection
   (lambda (conn)
     (define rows (list-scholars conn cohort))
     (print-rows '("ID" "Scholar" "Cohort" "Status" "Risk") rows))))

(define (handle-log-checkin)
  (define scholar-id #f)
  (define checkin-date #f)
  (define mood #f)
  (define stress #f)
  (define engagement #f)
  (define notes #f)
  (define flagged #f)
  (define tags #f)
  (run-with-args
   rest
   (lambda ()
     (command-line
      #:program "gs-wellbeing-pulse log-checkin"
      #:once-each
      ["--scholar-id" value "Scholar id" (set! scholar-id (parse-int value "scholar-id"))]
      ["--date" value "Check-in date" (set! checkin-date value)]
      ["--mood" value "Mood score" (set! mood (parse-score value "mood"))]
      ["--stress" value "Stress score" (set! stress (parse-score value "stress"))]
      ["--engagement" value "Engagement score" (set! engagement (parse-score value "engagement"))]
      ["--notes" value "Notes" (set! notes value)]
      ["--flagged" value "Flagged" (set! flagged (parse-bool value))]
      ["--tags" value "Comma-separated tags" (set! tags (parse-tags value))]))))
  (require-arg scholar-id "--scholar-id")
  (require-arg checkin-date "--date")
  (require-arg mood "--mood")
  (require-arg stress "--stress")
  (require-arg engagement "--engagement")
  (require-arg notes "--notes")
  (define final-flagged (if (boolean? flagged) flagged (compute-flagged mood stress engagement)))
  (with-connection
   (lambda (conn)
     (define checkin-id (log-checkin! conn scholar-id checkin-date mood stress engagement notes final-flagged tags))
     (displayln (format "Logged check-in with id ~a" checkin-id)))))

(define (handle-list-checkins)
  (define scholar-id #f)
  (define cohort #f)
  (define limit 25)
  (run-with-args
   rest
   (lambda ()
     (command-line
      #:program "gs-wellbeing-pulse list-checkins"
      #:once-each
      ["--scholar-id" value "Scholar id" (set! scholar-id (parse-int value "scholar-id"))]
      ["--cohort" value "Cohort" (set! cohort value)]
      ["--limit" value "Limit" (set! limit (parse-int value "limit"))]))))
  (with-connection
   (lambda (conn)
     (define rows (list-checkins conn scholar-id cohort limit))
     (print-rows
      '("ID" "Date" "Scholar" "Cohort" "Mood" "Stress" "Engage" "Flagged" "Notes" "Tags")
      rows))))

(define (handle-weekly-summary)
  (define week-start #f)
  (define cohort #f)
  (run-with-args
   rest
   (lambda ()
     (command-line
      #:program "gs-wellbeing-pulse weekly-summary"
      #:once-each
      ["--week-start" value "Week start (YYYY-MM-DD)" (set! week-start value)]
      ["--cohort" value "Cohort" (set! cohort value)])))
  (require-arg week-start "--week-start")
  (with-connection
   (lambda (conn)
     (define rows (weekly-summary conn week-start cohort))
     (print-rows '("Cohort" "Checkins" "Avg Mood" "Avg Stress" "Avg Engage" "Flagged") rows))))

(define (dispatch)
  (case cmd
    [("init-db") (handle-init-db)]
    [("seed-db") (handle-seed-db)]
    [("add-cohort") (handle-add-cohort)]
    [("add-scholar") (handle-add-scholar)]
    [("list-cohorts") (handle-list-cohorts)]
    [("list-scholars") (handle-list-scholars)]
    [("log-checkin") (handle-log-checkin)]
    [("list-checkins") (handle-list-checkins)]
    [("weekly-summary") (handle-weekly-summary)]
    [else (usage)]))

(module+ main
  (dispatch))
