# Group Scholar Wellbeing Pulse

Group Scholar Wellbeing Pulse is a Racket CLI that tracks scholar wellbeing check-ins, flags risk signals, and summarizes weekly cohort health. It stores data in Postgres so the ops team can keep longitudinal history and audit trails.

## Features
- Capture check-ins with mood, stress, and engagement scores.
- Automatic risk flagging for low mood, high stress, or low engagement.
- Tag stressors (housing, financial, workload) for follow-up routing.
- Weekly cohort summaries with averages and flagged counts.
- Cohort and scholar directories for quick filtering.

## Tech
- Racket 9
- PostgreSQL (production)

## Setup
1. Install dependencies (Racket includes `db` by default).
2. Copy `env.example` to `.env` and export values.
3. Initialize and seed the database.

```bash
racket src/main.rkt init-db
racket src/main.rkt seed-db
```

## Environment variables
- `DB_HOST`
- `DB_PORT` (default 5432)
- `DB_NAME` (default `ralph`)
- `DB_USER` (default `ralph`)
- `DB_PASSWORD`
- `DB_SSLMODE` (default `disable` for this Postgres host)

## Usage
```bash
racket src/main.rkt list-cohorts
racket src/main.rkt add-cohort --name "Rise Cohort" --start 2026-01-10
racket src/main.rkt add-scholar --name "Taylor Brooks" --cohort "Rise Cohort" --status active --risk-level low
racket src/main.rkt log-checkin --scholar-id 1 --date 2026-02-07 --mood 6 --stress 5 --engagement 7 --notes "On track with coursework." --tags workload
racket src/main.rkt list-checkins --limit 10
racket src/main.rkt weekly-summary --week-start 2026-02-03
```

## Schema
All tables live under the `groupscholar_wellbeing_pulse` schema.
- `cohorts`
- `scholars`
- `checkins`
- `pulse_tags`
- `checkin_tags`

## Tests
```bash
raco test test/test_main.rkt
```

## Notes
- This CLI is intended for production use with environment variables and does not include credentials in source.
