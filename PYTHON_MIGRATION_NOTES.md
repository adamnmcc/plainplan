# Python Backend Notes

The API backend is Python 3.11 FastAPI, deployed to AWS Lambda via Mangum.

## Source

- Application: `python_service/main.py`
- Lambda handler: `python_service/lambda_handler.py`
- Dependencies: `requirements-python.txt`

## Run locally

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-python.txt
```

Set env vars:

- `DB_BACKEND=postgres` with `DATABASE_URL`, or `DB_BACKEND=rds_data_api` with:
  - `RDS_CLUSTER_ARN`, `RDS_SECRET_ARN`, `RDS_DATABASE_NAME`, `AWS_REGION`
- `OPENROUTER_API_KEY`
- `OPENROUTER_BASE_URL` (optional, defaults to `https://openrouter.ai/api/v1`)
- `STATS_SECRET` (optional, for `/api/stats`)

Start:

```bash
uvicorn python_service.main:app --host 0.0.0.0 --port 3000
```

## Lambda deployment

Build and packaging is handled by `scripts/build_lambda_python.sh`. The zip includes:

- `python_service/` source
- Installed pip dependencies
- `public/` and `test-fixtures/` (for sample plan endpoint)

Terraform handler: `python_service.lambda_handler.handler`

## Known limitations

- In-memory rate limiting is not distributed across Lambda instances.
