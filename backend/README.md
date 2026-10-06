# Kilowatch backend

The comparison service for the Kilowatch iOS app. Vercel Functions (Node) with a private Vercel Blob store. No accounts, no email: the app registers an anonymous user and keeps a bearer token.

## What it does

- **Neighbor cohorts.** Users who opt in submit kWh per billing period plus a ZIP and home profile. A cron job every six hours groups them into cohorts (ZIP, home type, bedrooms, electric heat) and publishes only quantiles for cohorts with at least 20 households. Smaller cohorts fall back to broader ones (same ZIP, then nearby ZIPs).
- **Friends.** Mutual opt-in through a short invite code. A friend sees the percentage difference, normalized per bedroom. Exact kWh only if that friend turned it on.
- **Deletion.** `DELETE /api/me` erases the user and unlinks them from friends.

## Endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/api/register` | none | Create an anonymous user. Returns `{ userId, token }`. |
| GET / PUT / DELETE | `/api/me` | bearer | Read or update display name, ZIP, home profile, privacy. Delete everything. |
| PUT | `/api/me/usage` | bearer | Replace submitted usage: `{ periods: [{ periodStart, periodEnd, kWh }] }`. |
| GET | `/api/me/comparison?month=YYYY-MM` | bearer | Neighbor cohort stats and friend comparisons for a month. |
| POST | `/api/invites` | bearer | Create an invite code. |
| POST | `/api/invites/accept` | bearer | `{ code }` → mutual friendship. |
| GET | `/api/cron/aggregate` | `CRON_SECRET` | Recompute cohorts. Scheduled in `vercel.json`. |
| GET | `/api/health` | none | Liveness plus cohort freshness. |

Auth header: `Authorization: Bearer <userId>.<token>`. Tokens are stored hashed.

## Storage

Private Blob store, one JSON document each: `users/<id>.json`, `invites/<code>.json`, `cohorts/latest.json`. See `lib/store.ts`; it is the only module that knows about Blob, so swapping in Postgres is contained.

## Environment

- `BLOB_READ_WRITE_TOKEN` — added automatically when the Blob store is connected to the project.
- `CRON_SECRET` — protects the aggregation endpoint. Vercel sends it on scheduled runs.
- `MIN_COHORT_SIZE` — optional, default 20. Do not lower in production.

## Develop

```bash
npm install
npm run typecheck
npm test
```

Deploys from the `backend/` root directory of the repo on every push to `main`.
