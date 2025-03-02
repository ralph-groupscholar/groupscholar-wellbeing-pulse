#lang racket

(require db
         racket/string)

(provide with-connection
         init-db!
         seed-db!
         add-cohort!
         add-scholar!
         log-checkin!
         list-checkins
         weekly-summary
         list-cohorts
         list-scholars)

(define (env name [default #f])
  (or (getenv name) default))

(define (string->port value)
  (define parsed (string->number value))
  (if (and parsed (integer? parsed)) parsed 5432))

(define (ssl-enabled?)
  (define sslmode (string-downcase (env "DB_SSLMODE" "disable")))
  (not (member sslmode '("disable" "off" "false"))))

(define (open-connection)
  (define host (env "DB_HOST"))
  (define port (string->port (env "DB_PORT" "5432")))
  (define db-name (env "DB_NAME" "ralph"))
  (define user (env "DB_USER" "ralph"))
  (define password (env "DB_PASSWORD"))
  (unless (and host password)
    (raise-user-error 'db "Missing DB_HOST or DB_PASSWORD environment variables."))
  (define conn
    (postgresql-connect
     #:server host
     #:port port
     #:database db-name
     #:user user
     #:password password
     #:ssl? (ssl-enabled?)))
  (query-exec conn "set search_path to groupscholar_wellbeing_pulse")
  conn)

(define (with-connection proc)
  (define conn (open-connection))
  (dynamic-wind
    void
    (lambda () (proc conn))
    (lambda () (disconnect conn))))

(define schema-sql
  (string-join
   (list
    "create schema if not exists groupscholar_wellbeing_pulse;"
    "create table if not exists cohorts ("
    "  id serial primary key,"
    "  name text not null unique,"
    "  start_date date not null"
    ");"
    "create table if not exists scholars ("
    "  id serial primary key,"
    "  cohort_id integer not null references cohorts(id),"
    "  full_name text not null,"
    "  status text not null,"
    "  risk_level text not null"
    ");"
    "create table if not exists checkins ("
    "  id serial primary key,"
    "  scholar_id integer not null references scholars(id),"
    "  checkin_date date not null,"
    "  mood_score integer not null,"
    "  stress_score integer not null,"
    "  engagement_score integer not null,"
    "  notes text not null,"
    "  flagged boolean not null,"
    "  created_at timestamptz not null default now()"
    ");"
    "create table if not exists pulse_tags ("
    "  id serial primary key,"
    "  tag text not null unique"
    ");"
    "create table if not exists checkin_tags ("
    "  checkin_id integer not null references checkins(id) on delete cascade,"
    "  tag_id integer not null references pulse_tags(id) on delete cascade,"
    "  primary key (checkin_id, tag_id)"
    ");"
    "create index if not exists idx_checkins_date on checkins(checkin_date);"
    "create index if not exists idx_checkins_flagged on checkins(flagged);"
    "create index if not exists idx_scholars_cohort on scholars(cohort_id);")
   "\n"))

(define seed-sql
  (string-join
   (list
    "insert into cohorts (name, start_date) values"
    "  ('North Star Cohort', '2025-08-15'),"
    "  ('Launchpad Cohort', '2025-09-05')"
    "on conflict (name) do nothing;"
    "insert into scholars (cohort_id, full_name, status, risk_level) values"
    "  ((select id from cohorts where name = 'North Star Cohort'), 'Amaya Lewis', 'active', 'low'),"
    "  ((select id from cohorts where name = 'North Star Cohort'), 'Jordan Nguyen', 'active', 'medium'),"
    "  ((select id from cohorts where name = 'Launchpad Cohort'), 'Riley Patel', 'active', 'low'),"
    "  ((select id from cohorts where name = 'Launchpad Cohort'), 'Sasha Ortiz', 'active', 'high')"
    "on conflict do nothing;"
    "insert into pulse_tags (tag) values"
    "  ('financial-stress'),"
    "  ('housing'),"
    "  ('workload'),"
    "  ('health')"
    "on conflict (tag) do nothing;"
    "insert into checkins (scholar_id, checkin_date, mood_score, stress_score, engagement_score, notes, flagged) values"
    "  ((select id from scholars where full_name = 'Amaya Lewis'), '2026-02-03', 7, 4, 8, 'Feels balanced, excited about upcoming workshop.', false),"
    "  ((select id from scholars where full_name = 'Jordan Nguyen'), '2026-02-04', 4, 7, 5, 'Busy with midterms and work shift adjustments.', true),"
    "  ((select id from scholars where full_name = 'Riley Patel'), '2026-02-05', 8, 3, 9, 'Momentum strong and mentoring peer.', false),"
    "  ((select id from scholars where full_name = 'Sasha Ortiz'), '2026-02-06', 3, 8, 3, 'Housing transition causing stress.', true)
    "
    "on conflict do nothing;"
    "insert into checkin_tags (checkin_id, tag_id) values"
    "  ((select id from checkins where notes like 'Busy with midterms%'), (select id from pulse_tags where tag = 'workload')),
    "  ((select id from checkins where notes like 'Housing transition%'), (select id from pulse_tags where tag = 'housing')),
    "  ((select id from checkins where notes like 'Housing transition%'), (select id from pulse_tags where tag = 'financial-stress'))
    "on conflict do nothing;")
   "\n"))

(define (init-db! conn)
  (query-exec conn schema-sql))

(define (seed-db! conn)
  (query-exec conn seed-sql))

(define (add-cohort! conn name start-date)
  (query-row conn
             "insert into cohorts (name, start_date) values ($1, $2) returning id"
             name start-date))

(define (add-scholar! conn name cohort status risk-level)
  (query-row conn
             "insert into scholars (cohort_id, full_name, status, risk_level) values ((select id from cohorts where name = $1), $2, $3, $4) returning id"
             cohort name status risk-level))

(define (ensure-tags! conn tags)
  (for ([tag tags])
    (query-exec conn
                "insert into pulse_tags (tag) values ($1) on conflict (tag) do nothing"
                tag)))

(define (log-checkin! conn scholar-id checkin-date mood stress engagement notes flagged tags)
  (define row
    (query-row conn
               "insert into checkins (scholar_id, checkin_date, mood_score, stress_score, engagement_score, notes, flagged) values ($1, $2, $3, $4, $5, $6, $7) returning id"
               scholar-id checkin-date mood stress engagement notes flagged))
  (define checkin-id (vector-ref row 0))
  (when (and tags (not (null? tags)))
    (ensure-tags! conn tags)
    (for ([tag tags])
      (query-exec conn
                  "insert into checkin_tags (checkin_id, tag_id) values ($1, (select id from pulse_tags where tag = $2)) on conflict do nothing"
                  checkin-id tag)))
  checkin-id)

(define (list-cohorts conn)
  (query-rows conn
              "select id, name, start_date from cohorts order by start_date"))

(define (list-scholars conn [cohort #f])
  (define params '())
  (define clauses '())
  (define idx 1)
  (when cohort
    (set! clauses (append clauses (list (format "c.name = $~a" idx))))
    (set! params (append params (list cohort)))
    (set! idx (add1 idx)))
  (define where (if (null? clauses) "" (string-append " where " (string-join clauses " and "))))
  (define sql
    (string-append
     "select s.id, s.full_name, c.name, s.status, s.risk_level "
     "from scholars s join cohorts c on s.cohort_id = c.id"
     where
     " order by c.name, s.full_name"))
  (apply query-rows conn sql params))

(define (list-checkins conn [scholar-id #f] [cohort #f] [limit 25])
  (define params '())
  (define clauses '())
  (define idx 1)
  (when scholar-id
    (set! clauses (append clauses (list (format "s.id = $~a" idx))))
    (set! params (append params (list scholar-id)))
    (set! idx (add1 idx)))
  (when cohort
    (set! clauses (append clauses (list (format "c.name = $~a" idx))))
    (set! params (append params (list cohort)))
    (set! idx (add1 idx)))
  (define where (if (null? clauses) "" (string-append " where " (string-join clauses " and "))))
  (define sql
    (string-append
     "select k.id, k.checkin_date, s.full_name, c.name, "
     "k.mood_score, k.stress_score, k.engagement_score, k.flagged, "
     "k.notes, coalesce(string_agg(t.tag, ', ' order by t.tag), '') "
     "from checkins k "
     "join scholars s on k.scholar_id = s.id "
     "join cohorts c on s.cohort_id = c.id "
     "left join checkin_tags ct on ct.checkin_id = k.id "
     "left join pulse_tags t on t.id = ct.tag_id "
     where
     " group by k.id, s.full_name, c.name "
     "order by k.checkin_date desc, k.id desc "
     (format "limit ~a" limit)))
  (apply query-rows conn sql params))

(define (weekly-summary conn week-start [cohort #f])
  (define params (list week-start))
  (define idx 2)
  (define cohort-clause "")
  (when cohort
    (set! cohort-clause (format " and c.name = $~a" idx))
    (set! params (append params (list cohort))))
  (define sql
    (string-append
     "select c.name, count(*) as checkins, "
     "round(avg(k.mood_score)::numeric, 2) as avg_mood, "
     "round(avg(k.stress_score)::numeric, 2) as avg_stress, "
     "round(avg(k.engagement_score)::numeric, 2) as avg_engagement, "
     "sum(case when k.flagged then 1 else 0 end) as flagged_count "
     "from checkins k "
     "join scholars s on k.scholar_id = s.id "
     "join cohorts c on s.cohort_id = c.id "
     "where k.checkin_date >= $1 and k.checkin_date < ($1::date + interval '7 days')"
     cohort-clause
     " group by c.name order by c.name"))
  (apply query-rows conn sql params))
