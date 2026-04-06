# PlainPlan

AI-powered Terraform plan analyzer. Send `terraform show -json` output to the API and get a structured risk analysis back.

## Architecture

- **Website**: Static site in S3 behind CloudFront
- **API**: Python 3.11 FastAPI on AWS Lambda (via Mangum)
- **Gateway**: API Gateway HTTP API
- **Database**: Aurora Serverless v2 PostgreSQL (RDS Data API)
- **Secrets**: AWS Secrets Manager (OpenRouter key, stats token)
- **DNS/TLS**: Route53 + ACM (automated by Terraform)
- **IaC**: Terraform with S3 backend
- **CI/CD**: GitHub Actions (deploy on push to main)

Hosting details for the website and API are documented in `docs/infrastructure.md`.

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | None | Health check |
| GET | `/api` | None | API info and endpoint list |
| GET | `/api/example` | None | Sample Terraform plan for testing |
| POST | `/api/keys` | None | Generate an API key |
| GET | `/api/keys/verify` | Bearer | Verify an API key |
| POST | `/api/analyze` | Bearer | Analyze a Terraform plan |

## Local Development

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-python.txt

# Set env vars (see python_service section)
export DB_BACKEND=postgres DATABASE_URL="postgresql://..."
export OPENROUTER_API_KEY="sk-or-v1-..."

uvicorn python_service.main:app --host 0.0.0.0 --port 3000
```

## Deployment

### Prerequisites

- AWS account with Route53 hosted zone for your domain
- IAM user with deploy permissions (see `terraform/iam-policy-terraform-deploy.json`)
- GitHub repo secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`

### First-time setup

1. Create the S3 state bucket and DynamoDB lock table:

```bash
aws s3api create-bucket --bucket <name>-tfstate-<account-id> --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1
aws s3api put-bucket-versioning --bucket <name> --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket <name> \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
```

2. Configure `terraform/dev.backend.hcl` with your bucket details.

3. Configure `terraform/dev.tfvars` with your settings.

4. Deploy:

```bash
cd terraform
terraform init -backend-config=dev.backend.hcl
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

5. Populate secrets (Terraform creates empty shells on first deploy):

```bash
aws secretsmanager put-secret-value \
  --secret-id plainplan/dev/OPENROUTER_API_KEY \
  --secret-string 'sk-or-v1-...' --region eu-west-1

aws secretsmanager put-secret-value \
  --secret-id plainplan/dev/STATS_SECRET \
  --secret-string 'your-random-token' --region eu-west-1
```

6. Re-deploy to pick up the real secret values.

### CI/CD

Pushes to `main` trigger the GitHub Actions workflow (`.github/workflows/deploy-aws.yml`), which:

1. Builds the Lambda zip
2. Runs `terraform init` / `plan` / `apply` using the `dev.backend.hcl` and `dev.tfvars` files in the repo
3. Bootstraps the Aurora schema (if enabled)
4. Runs post-deploy smoke tests against all API endpoints

Secrets are read directly from AWS Secrets Manager by Terraform — no secrets flow through CI.

### Adding a new environment

1. Create `terraform/<env>.tfvars` and `terraform/<env>.backend.hcl`
2. Create a new S3 state key (or bucket) for the environment
3. Create a GitHub Actions environment with `AWS_REGION` secret

## Project Structure

```
python_service/     Python FastAPI application + Lambda handler
terraform/          Infrastructure as Code
  dev.tfvars        Dev environment variables
  dev.backend.hcl   Dev S3 backend config
scripts/            Build and deploy scripts
schema/             PostgreSQL schema
test-fixtures/      Sample plan data
public/             Static frontend pages
```
