# PlainPlan AWS Migration Plan

Date: 2026-04-02
Status: **Deployed** — dev environment live on AWS

## Current State

The migration is complete. PlainPlan runs on AWS with:

- **API**: Python 3.11 FastAPI on Lambda (via Mangum)
- **Gateway**: API Gateway HTTP API
- **Database**: Aurora Serverless v2 PostgreSQL (RDS Data API, no VPC/NAT needed)
- **Secrets**: AWS Secrets Manager (Terraform creates shells, values populated via CLI)
- **DNS/TLS**: Route53 + ACM (fully automated by Terraform)
- **State**: S3 backend with lockfile
- **CI/CD**: GitHub Actions — deploy on push to main with post-deploy smoke tests

## What was done

### Completed

- [x] Python 3.11 FastAPI backend with Lambda handler (Mangum)
- [x] Terraform IaC for full stack (Lambda, API Gateway, Aurora, IAM, CloudWatch)
- [x] Aurora Serverless v2 with RDS Data API (no VPC/NAT/RDS Proxy needed)
- [x] Schema bootstrap via Data API script (`scripts/bootstrap_aurora_data_api.py`)
- [x] Secrets Manager for app secrets — Terraform creates shells, reads values via data sources
- [x] SSM Parameter Store for non-sensitive config
- [x] S3 remote state with lockfile
- [x] ACM certificate creation + Route53 DNS validation (fully automated)
- [x] Custom domain setup (Route53 alias A record to API Gateway)
- [x] GitHub Actions CI/CD — build, init, plan, apply, schema bootstrap, smoke tests
- [x] Post-deploy smoke tests covering all API endpoints
- [x] No secrets flow through CI — Terraform reads directly from Secrets Manager

### Remaining / Future

- [ ] Static frontend to S3 + CloudFront (currently bundled in Lambda)
- [ ] Distributed rate limiting (currently in-memory, not multi-instance safe)
- [ ] CloudWatch alarms (Lambda errors, 5xx, p95 latency)
- [ ] WAF on API Gateway
- [ ] Production environment (`prod.tfvars` + `prod.backend.hcl`)
- [ ] Load testing baseline

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| IaC | Terraform | Team familiarity, multi-cloud option |
| Compute | Lambda + Mangum | No always-on cost, scales to zero |
| Database | Aurora Serverless v2 + Data API | No VPC/NAT needed, Lambda-safe |
| Secrets | Secrets Manager (not SSM SecureString) | Native rotation support, Terraform data sources |
| DNS/TLS | Route53 + ACM in Terraform | Fully automated, no manual cert/DNS steps |
| CI secrets | None in CI | Terraform reads from AWS directly |
| State backend | S3 + lockfile | Native Terraform, no DynamoDB needed |

## Risk Register

| Risk | Mitigation | Status |
|------|-----------|--------|
| Lambda cold starts | Monitor p95, consider provisioned concurrency if needed | Monitor |
| API Gateway payload limits (10MB) | Acceptable for most Terraform plans | Accepted |
| Aurora not scale-to-zero | 0.5 ACU minimum, ~$43/mo idle | Accepted for dev |
| Rate limiting not distributed | In-memory works for single Lambda; move to DynamoDB if needed | Deferred |
| Cost spikes from AI calls | OpenRouter has per-request pricing; add budget alerts | Todo |
