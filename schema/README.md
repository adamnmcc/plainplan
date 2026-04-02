# PlanPlain — Database Schema

Full PostgreSQL schema for PlanPlain: an AI-powered Terraform plan analyzer with API key authentication and usage tracking.

## Tables

### `_migrations`
Migration tracking table. Created automatically on every deploy by `migrate.js`.

### `users`
Core user accounts. Subscription fields are synced by Polsia when a user subscribes via Stripe.

### `api_keys`
Bearer token API keys for authenticating `/api/analyze` requests. Raw key is shown to user once at creation (format: `pp_live_xxx`). Only the SHA-256 hash is stored.

### `analysis_logs`
Detailed log of every Terraform plan analysis.

### `api_requests`
Lightweight request log for dashboard metrics (request counts, error rates, response times).

## Migration Files

| File | Name | What it creates |
|------|------|-----------------|
| `001_api_keys_and_usage.js` | `api_keys_and_usage` | `api_keys`, `analysis_logs` + indexes |
| `002_api_requests_table.js` | `api_requests_table` | `api_requests` + indexes |

## Entity Relationships

```
users
  └── api_keys (user_id → users.id, CASCADE DELETE)
        └── analysis_logs (api_key_id → api_keys.id, SET NULL on delete)

api_requests  (standalone — no FK)
```

## Files

| File | Description |
|------|-------------|
| `schema.sql` | Full schema as `CREATE TABLE` / `CREATE INDEX` statements |
| `README.md` | This file |
| `../migrations/` | Source migration files (JS, run by `migrate.js`) |
| `../migrate.js` | Migration runner — runs on every deploy |
