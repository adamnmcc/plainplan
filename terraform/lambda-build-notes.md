# Lambda Packaging Notes

Current backend can run as FastAPI on AWS Lambda via Mangum.

Minimum expected files in the zip:

- Python source (including `python_service/`)
- installed Python dependencies (site-packages)
- Lambda adapter exporting `handler` from `python_service/lambda_handler.py`

Suggested packaging workflow:

1. Install dependencies to a build folder:
	`pip install -r requirements-python.txt -t build/python`
2. Copy source files into the same folder (`python_service/`, `public/`, `test-fixtures/`).
3. Zip folder contents into `../build/plainplan-lambda.zip`.
4. Keep Terraform `handler` as `python_service.lambda_handler.handler`.
