from mangum import Mangum

from .main import app

# AWS Lambda entrypoint for API Gateway v2 (HTTP API).
handler = Mangum(app)
