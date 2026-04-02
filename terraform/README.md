# Terraform — PlainPlan AWS Infrastructure

Provisions the PlainPlan backend stack:

- AWS Lambda (Python 3.11) for API compute
- API Gateway HTTP API
- CloudWatch logs (7-day retention)
- Aurora Serverless v2 PostgreSQL via the RDS Data API
- ACM certificate with automated Route53 DNS validation
- Custom domain mapping (automated via Route53)
- Secrets Manager for app secrets (OpenRouter API key, stats token)
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
| `dev.backend.hcl` | Dev S3 backend configuration |
| `config_secrets.tf` | Secrets Manager + SSM resources and seed values |
| `domain.tf` | ACM cert, Route53 validation, API Gateway custom domain |
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

## Custom domain

Set `custom_domain_name` and `route53_zone_name` in your tfvars. Terraform will:

1. Create an ACM certificate
2. Add DNS validation records in Route53
3. Wait for certificate validation
4. Create the API Gateway custom domain
5. Add an alias A record pointing to API Gateway

No manual DNS or certificate work needed.

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

Trigger: push to `main` or manual dispatch.

Required GitHub secrets (in `dev` environment):
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`

The workflow runs `terraform init -backend-config=dev.backend.hcl`, plans, applies, bootstraps Aurora schema, and runs post-deploy smoke tests.

## Adding a new environment

1. Create `<env>.tfvars` and `<env>.backend.hcl`
2. Create a new S3 state bucket or use a different key
3. Populate secrets under the new prefix (e.g. `plainplan/prod/*`)
4. Create a matching GitHub Actions environment with AWS credentials
