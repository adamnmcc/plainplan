import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    db_backend: str
    database_url: str
    aws_region: str
    rds_cluster_arn: str
    rds_secret_arn: str
    rds_database_name: str
    openrouter_api_key: str
    openrouter_base_url: str
    stats_secret: str
    polsia_analytics_slug: str


def get_settings() -> Settings:
    db_backend = os.getenv("DB_BACKEND", "postgres")
    database_url = os.getenv("DATABASE_URL", "")

    if db_backend == "postgres" and not database_url:
        raise RuntimeError("DATABASE_URL environment variable is required")

    if db_backend == "rds_data_api":
        required = {
            "RDS_CLUSTER_ARN": os.getenv("RDS_CLUSTER_ARN", ""),
            "RDS_SECRET_ARN": os.getenv("RDS_SECRET_ARN", ""),
            "RDS_DATABASE_NAME": os.getenv("RDS_DATABASE_NAME", ""),
        }
        missing = [name for name, value in required.items() if not value]
        if missing:
            raise RuntimeError(f"Missing Data API settings: {', '.join(missing)}")

    return Settings(
        db_backend=db_backend,
        database_url=database_url,
        aws_region=os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", "us-east-1")),
        rds_cluster_arn=os.getenv("RDS_CLUSTER_ARN", ""),
        rds_secret_arn=os.getenv("RDS_SECRET_ARN", ""),
        rds_database_name=os.getenv("RDS_DATABASE_NAME", ""),
        openrouter_api_key=os.getenv("OPENROUTER_API_KEY", os.getenv("OPENAI_API_KEY", "")),
        openrouter_base_url=os.getenv("OPENROUTER_BASE_URL", os.getenv("OPENAI_BASE_URL", "https://openrouter.ai/api/v1")),
        stats_secret=os.getenv("STATS_SECRET", ""),
        polsia_analytics_slug=os.getenv("POLSIA_ANALYTICS_SLUG", ""),
    )
