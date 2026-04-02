# Terraform Scaffold for PlainPlan (AWS Lambda + Aurora)

This folder provisions a low-cost backend stack for PlainPlan:

- AWS Lambda (Python 3.11) for API compute
- API Gateway HTTP API (cheaper than REST API)
- CloudWatch logs (7-day retention)
- Aurora Serverless v2 PostgreSQL via the RDS Data API
- Optional custom domain mapping for `api.plainplan.click`

## Cost-conscious choices

- No always-on compute.
- No VPC attachment for Lambda (avoids NAT and related costs).

## Database mode

- Default path: Aurora Serverless v2 with the RDS Data API.
- Fallback path: set `enable_aurora_serverless = false` and provide `database_url` only if you intentionally want an external Postgres service.

Important cost caveat:

- Aurora Serverless v2 is serverless in scaling behavior, but it is not free when idle and it does not scale to zero.
- The lowest idle setting is `0.5` ACU.
- This is still typically cheaper than adding a NAT gateway just to let Lambda reach a private RDS instance and the public internet.

## Prerequisites

- Terraform >= 1.6
- AWS credentials configured
- A Lambda zip artifact at the configured `lambda_zip_path`
- ACM certificate in same region if using custom domain

## Quick start

1. Copy vars:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Edit secrets/values in `terraform.tfvars`.

3. Deploy:

```bash
terraform init
terraform plan
terraform apply
```

4. Read outputs:

- `api_invoke_url`
- `custom_domain_target` (if custom domain enabled)

## Scripted build + deploy (recommended)

From repo root, create `.env` with these values:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION` (for example `us-east-1`)
- `ENABLE_AURORA_SERVERLESS` (`true` by default)
- `AURORA_DATABASE_NAME` (optional, default `plainplan`)
- `AURORA_ENGINE_VERSION` (optional, default `16.4`)
- `AURORA_MIN_CAPACITY` (optional, default `0.5`)
- `AURORA_MAX_CAPACITY` (optional, default `1`)
- `OPENROUTER_API_KEY`
- `OPENROUTER_BASE_URL` (optional, default `https://openrouter.ai/api/v1`)
- `STATS_SECRET`
- `PROJECT_NAME` (optional, default `plainplan`)
- `ENVIRONMENT` (optional, default `dev`)
- `CUSTOM_DOMAIN_NAME` (optional, for example `api.plainplan.click`)
- `ACM_CERTIFICATE_ARN` (required only for custom domain mapping)

Optional only when not using Aurora:

- `DATABASE_URL`

Optional but recommended for shared/CI deploys:

- `TF_STATE_BUCKET` (S3 bucket for Terraform remote state)
- `TF_STATE_KEY` (for example `plainplan/prod/terraform.tfstate`)
- `TF_STATE_REGION` (region of the S3 state bucket)
- `TF_LOCK_TABLE` (optional DynamoDB lock table name)

### Sync `.env` from AWS (recommended)

You can store deploy values in AWS and generate `.env` locally.

- Sensitive values: AWS Secrets Manager
- Non-sensitive config: SSM Parameter Store (or Secrets Manager as well)

The helper script looks up each key first in Secrets Manager and then in SSM:

```bash
npm run env:sync:aws -- --prefix plainplan/prod --region us-east-1
```

Lookup naming convention:

- Secrets Manager: `plainplan/prod/OPENROUTER_API_KEY`
- SSM: `/plainplan/prod/ENABLE_AURORA_SERVERLESS`

Required for Aurora path:

- `AWS_REGION`
- `OPENROUTER_API_KEY`
- `STATS_SECRET`
- `ENABLE_AURORA_SERVERLESS=true`

Optional depending on your setup:

- `OPENROUTER_BASE_URL` (defaults to `https://openrouter.ai/api/v1`)
- `DATABASE_URL` (only when Aurora is disabled)
- `ACM_CERTIFICATE_ARN`, `CUSTOM_DOMAIN_NAME`
- `TF_STATE_BUCKET`, `TF_STATE_REGION`, `TF_STATE_KEY`, `TF_LOCK_TABLE`

Then run:

```bash
npm run build:lambda:python
npm run deploy:aws:dev
```

The deploy script runs Terraform apply and performs a `/health` check on the API Gateway URL.

With the default Aurora path, the deploy script also bootstraps the schema in Aurora using the RDS Data API.

If `TF_STATE_BUCKET` is set, the script uses S3 remote state (recommended for CI/CD).

## plainplan.click DNS setup

If you set `custom_domain_name` and `acm_certificate_arn`, Terraform creates API Gateway custom domain resources and outputs a target domain.

At your registrar DNS panel, create a CNAME:

- Name: `api`
- Value: output `custom_domain_target.target_domain_name`

Then use `https://api.plainplan.click` as your API base.

To verify after DNS propagation:

```bash
curl -fsS https://api.plainplan.click/health
```

## Notes

- This scaffold assumes your app has a Lambda handler named `python_service.lambda_handler.handler`.
- Frontend can remain where it is for now, as requested.
- Later, you can move static frontend to S3 + CloudFront.

## GitHub Actions deploy-on-merge

Workflow file: `.github/workflows/deploy-aws.yml`

Trigger:

- Pushes to `main` or `master` (including PR merges)
- Manual dispatch from Actions tab

Required GitHub repository secrets:

- `AWS_ACCESS_KEY_ID` or `AWS_IAM_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY` or `AWS_IAM_SECRET_ACCESS_KEY`
- `AWS_REGION`

Recommended GitHub repository variables:

- `AWS_CONFIG_PREFIX` (default lookup prefix: `plainplan/dev`)

Store deploy/app configuration in AWS under that prefix:

- Secrets Manager for sensitive values (for example `OPENROUTER_API_KEY`, `STATS_SECRET`)
- SSM Parameter Store for non-sensitive values (for example `ENABLE_AURORA_SERVERLESS`, `AURORA_MIN_CAPACITY`)

The workflow syncs `.env` from AWS at runtime using `scripts/sync_env_from_aws.sh` and only requires AWS credentials in GitHub.

Recommended repository variables:

- `PROJECT_NAME` (default: `plainplan`)
- `ENVIRONMENT` (default: `prod`)
- `ENABLE_AURORA_SERVERLESS` (default: `true`)
- `AURORA_DATABASE_NAME` (default: `plainplan`)
- `AURORA_ENGINE_VERSION` (default: `16.4`)
- `AURORA_MIN_CAPACITY` (default: `0.5`)
- `AURORA_MAX_CAPACITY` (default: `1`)
- `CUSTOM_DOMAIN_NAME` (default: `api.plainplan.click`)
- `TF_STATE_KEY` (default: `plainplan/prod/terraform.tfstate`)
