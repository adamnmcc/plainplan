# Terraform — PlainPlan AWS Infrastructure

Provisions the PlainPlan application stack:

- S3 bucket for website assets
- CloudFront distribution for the website
- AWS Lambda (Python 3.11) for API compute
- API Gateway HTTP API
- CloudWatch logs (7-day retention)
- Aurora Serverless v2 PostgreSQL via the RDS Data API
- Regional ACM certificate for the API domain
- `us-east-1` ACM certificate for the CloudFront website domain
- Route53 records for website and API domains
- Secrets Manager for app secrets (OpenRouter key, stats token)
- SSM Parameter Store for non-sensitive config

## Cost-conscious choices

- No always-on compute.
- No VPC attachment for Lambda (avoids NAT and related costs).

## Database mode

- Default path: Aurora Serverless v2 with the RDS Data API.
- Fallback path: set `enable_aurora_serverless = false` and provide `database_url` for external Postgres.

Aurora Serverless v2 does not scale to zero. The lowest idle setting is `0.5` ACU.

## Files

| File | Purpose |
|------|---------|
| `dev.tfvars` | Dev environment variables |
| `prod.tfvars` | Prod environment variables |
| `dev.backend.hcl` | Dev S3 backend configuration |
| `prod.backend.hcl` | Prod S3 backend configuration |
| `config_secrets.tf` | Secrets Manager + SSM resources and seed values |
| `domain.tf` | ACM cert, Route53 validation, API Gateway custom domain |
| `website.tf` | S3, CloudFront, website ACM, website DNS, website file upload |
| `aurora.tf` | Aurora Serverless v2 cluster and security group |
| `iam-policy-terraform-deploy.json` | Reference IAM policy for the deploy user |

## Prerequisites

- Terraform >= 1.6
- AWS credentials configured
- A Lambda zip artifact at `../build/plainplan-lambda.zip`
- Route53 hosted zone for your domain (if using custom domain)

## Quick start

```bash
terraform init -backend-config=dev.backend.hcl
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

For prod:

```bash
terraform init -backend-config=prod.backend.hcl
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

## Secrets management

Terraform creates Secrets Manager secrets with placeholder values on first deploy. Secrets are read directly by Terraform and injected into Lambda environment variables — no secrets flow through CI.

Populate real values after first deploy:

```bash
aws secretsmanager put-secret-value \
  --secret-id plainplan/dev/OPENROUTER_API_KEY \
  --secret-string 'sk-or-v1-...' --region eu-west-1

aws secretsmanager put-secret-value \
  --secret-id plainplan/dev/STATS_SECRET \
  --secret-string 'your-random-token' --region eu-west-1
```

Then re-deploy to update Lambda with the real values. Subsequent deploys won't overwrite your secrets (`lifecycle { ignore_changes }`).

## Domain model

Set `root_domain_name = "plainplan.click"` in your tfvars.

Terraform derives the public hostnames from `environment`:

| Environment | Website | API |
|---|---|---|
| `dev` | `dev.plainplan.click` | `dev.api.plainplan.click` |
| `prod` | `plainplan.click` | `api.plainplan.click` |

Terraform will:

1. Create a regional ACM certificate for the API domain
2. Create a `us-east-1` ACM certificate for the website domain
3. Add DNS validation records in Route53
4. Create the API Gateway custom domain for the API
5. Create the CloudFront distribution for the website
6. Add alias A records for both domains

No manual DNS or certificate work should be needed beyond having the hosted zone in Route53.

## Remote state

State is stored in S3 with the backend config in `<env>.backend.hcl`:

```hcl
bucket     = "plainplan-tfstate-<account-id>"
key        = "plainplan/dev/terraform.tfstate"
region     = "eu-west-1"
use_lockfile = true
```

## GitHub Actions CI/CD

Workflow: `.github/workflows/deploy-aws.yml`

Trigger:

- push to `main` or `master` deploys `dev`
- manual dispatch can deploy `dev` or `prod`

Required GitHub secrets per environment:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`

The workflow selects `<env>.backend.hcl` and `<env>.tfvars`, builds the Lambda artifact, applies Terraform, bootstraps the database, and runs API smoke tests.

## Adding a new environment

1. Create `<env>.tfvars` and `<env>.backend.hcl`
2. Create a new S3 state bucket or use a different key
3. Populate secrets under the new prefix (e.g. `plainplan/prod/*`)
4. Create a matching GitHub Actions environment with AWS credentials
