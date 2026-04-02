#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
ENV_FILE="$ROOT_DIR/.env"
TFVARS_FILE="$TF_DIR/terraform.tfvars"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[deploy] Missing $ENV_FILE"
  echo "[deploy] Create it with AWS and app secrets first."
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

ENABLE_AURORA_SERVERLESS="${ENABLE_AURORA_SERVERLESS:-false}"

required=(
  AWS_REGION
)

if [[ "$ENABLE_AURORA_SERVERLESS" != "true" ]]; then
  required+=( DATABASE_URL )
fi

for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "[deploy] Missing required env var: $key"
    exit 1
  fi
done

if [[ -n "${AWS_SESSION_TOKEN:-}" ]]; then
  export AWS_SESSION_TOKEN
fi

if [[ ! -f "$ROOT_DIR/build/plainplan-lambda.zip" ]]; then
  echo "[deploy] Lambda artifact missing. Building first..."
  "$ROOT_DIR/scripts/build_lambda_python.sh"
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "[deploy] terraform CLI is required"
  exit 1
fi

cat > "$TFVARS_FILE" <<EOF
project_name       = "${PROJECT_NAME:-plainplan}"
environment        = "${ENVIRONMENT:-dev}"
aws_region         = "${AWS_REGION}"
lambda_zip_path    = "../build/plainplan-lambda.zip"

database_url       = "${DATABASE_URL:-}"
enable_aurora_serverless = ${ENABLE_AURORA_SERVERLESS}
aurora_database_name     = "${AURORA_DATABASE_NAME:-plainplan}"
aurora_engine_version    = "${AURORA_ENGINE_VERSION:-16.4}"
aurora_min_capacity      = ${AURORA_MIN_CAPACITY:-0.5}
aurora_max_capacity      = ${AURORA_MAX_CAPACITY:-1}

custom_domain_name = "${CUSTOM_DOMAIN_NAME:-api.plainplan.click}"
acm_certificate_arn = "${ACM_CERTIFICATE_ARN:-}"
EOF

pushd "$TF_DIR" >/dev/null

if [[ -n "${TF_STATE_BUCKET:-}" ]]; then
  if [[ -z "${TF_STATE_REGION:-}" ]]; then
    echo "[deploy] TF_STATE_REGION is required when TF_STATE_BUCKET is set"
    exit 1
  fi

  TF_STATE_KEY="${TF_STATE_KEY:-plainplan/dev/terraform.tfstate}"
  BACKEND_ARGS=(
    -backend-config="bucket=${TF_STATE_BUCKET}"
    -backend-config="key=${TF_STATE_KEY}"
    -backend-config="region=${TF_STATE_REGION}"
  )

  if [[ -n "${TF_LOCK_TABLE:-}" ]]; then
    BACKEND_ARGS+=( -backend-config="dynamodb_table=${TF_LOCK_TABLE}" )
  fi

  echo "[deploy] terraform init (remote backend: s3://${TF_STATE_BUCKET}/${TF_STATE_KEY})"
  terraform init -reconfigure "${BACKEND_ARGS[@]}"
else
  echo "[deploy] terraform init (local backend disabled for this run)"
  terraform init -backend=false
fi

echo "[deploy] terraform apply"
terraform apply -auto-approve

API_URL="$(terraform output -raw api_invoke_url)"
CUSTOM_TARGET="$(terraform output -json custom_domain_target || true)"

if [[ "$ENABLE_AURORA_SERVERLESS" == "true" ]]; then
  if ! command -v aws >/dev/null 2>&1; then
    echo "[deploy] aws CLI is required to bootstrap the Aurora schema"
    exit 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[deploy] python3 is required to bootstrap the Aurora schema"
    exit 1
  fi

  AURORA_CLUSTER_ARN="$(terraform output -raw aurora_cluster_arn)"
  AURORA_SECRET_ARN="$(terraform output -raw aurora_secret_arn)"
  AURORA_DATABASE_NAME="$(terraform output -raw aurora_database_name)"

  echo "[deploy] Bootstrapping Aurora schema via Data API"
  python3 "$ROOT_DIR/scripts/bootstrap_aurora_data_api.py" \
    --cluster-arn "$AURORA_CLUSTER_ARN" \
    --secret-arn "$AURORA_SECRET_ARN" \
    --database "$AURORA_DATABASE_NAME" \
    --schema-file "$ROOT_DIR/schema/schema.sql" \
    --region "$AWS_REGION"
fi

popd >/dev/null

echo "[deploy] API URL: $API_URL"
echo "[deploy] Health check..."
curl -fsS "$API_URL/health" || {
  echo "[deploy] Health check failed"
  exit 1
}

if [[ -n "${CUSTOM_DOMAIN_NAME:-}" && -n "${ACM_CERTIFICATE_ARN:-}" ]]; then
  echo "[deploy] Custom domain target info from Terraform output:"
  echo "$CUSTOM_TARGET"
  echo "[deploy] Ensure DNS CNAME points ${CUSTOM_DOMAIN_NAME} to target_domain_name above, then verify:"
  echo "[deploy] curl -fsS https://${CUSTOM_DOMAIN_NAME}/health"
fi

echo "[deploy] Done."
