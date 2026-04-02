# PlainPlan AWS Migration Plan (Pre-Change)

Date: 2026-04-02
Status: Planning only (no code/infrastructure changes applied)

## 1) Goal
Migrate `plainplan` from a single Express service to a scalable AWS architecture using API Gateway + Lambda, while keeping behavior stable and minimizing downtime.

## 2) Recommended Target Architecture

- **API layer**: Amazon API Gateway (HTTP API)
- **Compute**: AWS Lambda (Node.js 20)
- **Database**: Amazon RDS PostgreSQL (or Aurora PostgreSQL Serverless v2)
- **DB connection protection**: RDS Proxy (important for Lambda burst traffic)
- **Static web** (`public/*`): S3 + CloudFront
- **Secrets**: AWS Secrets Manager + IAM roles
- **Rate limiting store**: Redis (ElastiCache) or DynamoDB (replace in-memory map)
- **Observability**: CloudWatch Logs + Metrics + X-Ray + alarms
- **Custom domain**: Route 53 + ACM + API Gateway custom domain mapping

## 3) Current State Constraints (from code)

- App is one monolithic Express server (`server.js`) with mixed concerns:
  - API routes
  - static frontend pages
  - `/dashboard` server-rendered file serving
- Rate limit middleware is **in-memory** (`middleware/rate-limit.js`) and not multi-instance safe.
- DB migrations run via startup script (`migrate.js`) and assume single service lifecycle.
- API request metrics are written synchronously to Postgres (`api_requests`, `analysis_logs`).

## 4) Required Changes (What must change)

### A. Runtime / Entrypoint
- Add Lambda-compatible handler (via `@vendia/serverless-express` or direct adapter).
- Keep Express app creation isolated so it can run both locally and in Lambda.

### B. Static Assets Split
- Remove static serving responsibility from Lambda for `public/*`.
- Publish landing/docs/dashboard to S3 + CloudFront.
- Keep API only in Lambda.

### C. Rate Limiting
- Replace in-memory `Map` with distributed store:
  - Option 1: Redis sliding window (fastest)
  - Option 2: DynamoDB token bucket/sliding window (fully serverless)

### D. Database Connectivity
- Move from direct PG pool to RDS Proxy endpoint.
- Ensure pool settings are Lambda-safe (small pool, short idle timeout).

### E. Config / Secrets
- Move env vars to Secrets Manager/SSM:
  - `DATABASE_URL`
  - `OPENROUTER_API_KEY`
  - `OPENROUTER_BASE_URL` (if used)
  - `STATS_SECRET`
- Remove hard-coded host URLs from route responses where possible.

### F. Migrations Process
- Decouple migrations from app boot.
- Run migrations in CI/CD deployment step (one-time per deploy).

### G. API Gateway Contract
- Ensure payload size limits are acceptable for Terraform plans.
- Add WAF (optional but recommended) and request validation.

### H. Monitoring / Operations
- Add structured JSON logs and correlation IDs.
- Create CloudWatch alarms:
  - Lambda errors > threshold
  - 5xx from API Gateway
  - p95 latency
  - DB connection saturation

## 5) Proposed Migration Phases

## Phase 0: Baseline & Safety (1-2 days)
- Freeze API contract (request/response samples)
- Add regression tests for key endpoints
- Add load test baseline (RPS, latency, error rate)
- Define rollback criteria

Exit criteria:
- Baseline metrics captured
- API compatibility tests pass in current environment

## Phase 1: Refactor for Deployability (2-4 days)
- Extract app construction into `app.js` (Express instance)
- Keep `server.js` for local dev only
- Add Lambda handler (`lambda.js`)
- Remove startup migration coupling

Exit criteria:
- Local app works unchanged
- Lambda handler works in local emulation

## Phase 2: AWS Infra Provisioning (2-5 days)
- Provision API Gateway, Lambda, IAM roles
- Provision RDS/Aurora + RDS Proxy
- Provision Secrets Manager, CloudWatch dashboards/alarms
- Provision S3 + CloudFront for static site

Exit criteria:
- Test environment reachable via API Gateway URL
- Static site served via CloudFront

## Phase 3: Stateful Concerns Migration (2-4 days)
- Replace in-memory rate limiter with Redis or DynamoDB
- Validate dashboard/stat endpoints still accurate

Exit criteria:
- Rate limiting works across concurrent Lambdas
- No behavior regression in auth/analyze routes

## Phase 4: Domain & TLS Cutover (1-2 days)
- Buy domain (`plainplan.io` / `.dev` / `.app`)
- Configure Route 53 hosted zone
- Issue ACM cert in region for API Gateway custom domain
- Map `api.<domain>` and `www.<domain>` / root
- Gradual DNS cutover with low TTL

Exit criteria:
- API and web are reachable on production domain with HTTPS

## Phase 5: Production Ramp (2-5 days)
- Canary traffic (10% -> 50% -> 100%)
- Monitor latency, error rates, DB load, cost
- Finalize rollback point and decommission old Render service

Exit criteria:
- Stable SLOs for 7 days
- Old infra retired

## 6) Rollback Plan

- Keep Render deployment alive until Phase 5 sign-off.
- DNS rollback by restoring old A/CNAME targets (TTL <= 60s during cutover).
- Keep database backups and point-in-time recovery enabled.

## 7) Naming & Domain Recommendation

Service name `plainplan` is strong:
- Clear meaning (plain-language plan review)
- Memorable and product-relevant
- Works well for infra/dev tooling audience

Before committing:
- Check trademark availability in your target regions.
- Check domain availability (`plainplan.io`, `plainplan.dev`, `plainplan.app`).
- Reserve social handles if branding matters.

## 8) Suggested Deliverables Before First Code Change

1. AWS architecture decision record (Lambda + API Gateway confirmed)
2. IaC choice (CDK/Terraform/Serverless Framework)
3. Environment matrix (`dev`, `staging`, `prod`)
4. Contract tests for `/api/analyze`, `/api/keys`, `/api/dashboard`
5. Domain purchased and certificate strategy documented

## 9) Risk Register (Top Items)

- Lambda cold starts affecting p95 latency
- DB connection exhaustion during bursts (mitigate with RDS Proxy)
- API Gateway payload limits for very large plans
- Incomplete migration of static pages/dashboard
- Cost spikes from uncontrolled retries or AI calls

## 10) Success Metrics

- p95 latency <= current baseline + 20%
- Error rate < 1%
- No auth/rate-limit regressions
- Zero data loss in `analysis_logs` and `api_requests`
- Cost per 1,000 requests within agreed threshold
