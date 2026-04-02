# Python Backend Migration Notes

This repository now includes a Python backend implementation in [python_service/main.py](python_service/main.py).

## Scope

- Frontend kept as-is (`public/*`).
- API behavior mirrored from Node backend where practical.
- Lambda-ready handler included at [python_service/lambda_handler.py](python_service/lambda_handler.py).

## Run locally

1. Install dependencies:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-python.txt
```

2. Set env vars:

- `DB_BACKEND=postgres` with `DATABASE_URL`, or `DB_BACKEND=rds_data_api` with:
- `RDS_CLUSTER_ARN`
- `RDS_SECRET_ARN`
- `RDS_DATABASE_NAME`
- `AWS_REGION`
- `OPENROUTER_API_KEY`
- `OPENROUTER_BASE_URL` (optional)
- `STATS_SECRET` (optional for `/api/stats`)
- `POLSIA_ANALYTICS_SLUG` (optional)

3. Start server:

```bash
uvicorn python_service.main:app --host 0.0.0.0 --port 3000
```

## Terraform alignment

If deploying Python Lambda, update Lambda runtime/handler in Terraform:

- runtime: `python3.11`
- handler: `python_service.lambda_handler.handler`

Package your code and dependencies into the zip used by Terraform.

## Known parity gaps

- In-memory rate limiting remains non-distributed (same limitation as previous implementation).
- Some error text/details may differ slightly from Node responses.
