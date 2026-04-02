from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Apply schema.sql to Aurora Serverless via the RDS Data API")
    parser.add_argument("--cluster-arn", required=True)
    parser.add_argument("--secret-arn", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--schema-file", required=True)
    parser.add_argument("--region", default="")
    return parser.parse_args()


def split_sql(sql_text: str) -> list[str]:
    without_comments = re.sub(r"--.*$", "", sql_text, flags=re.MULTILINE)
    statements = [statement.strip() for statement in without_comments.split(";")]
    return [statement for statement in statements if statement]


def run_statement(cluster_arn: str, secret_arn: str, database: str, statement: str, region: str) -> None:
    command = [
        "aws",
        "rds-data",
        "execute-statement",
        "--resource-arn",
        cluster_arn,
        "--secret-arn",
        secret_arn,
        "--database",
        database,
        "--sql",
        statement,
    ]
    if region:
        command.extend(["--region", region])
    subprocess.run(command, check=True, capture_output=True, text=True)


def main() -> int:
    args = parse_args()
    schema_path = Path(args.schema_file)
    statements = split_sql(schema_path.read_text(encoding="utf-8"))
    print(f"[bootstrap] Applying {len(statements)} SQL statements via Data API")

    for index, statement in enumerate(statements, start=1):
        run_statement(args.cluster_arn, args.secret_arn, args.database, statement, args.region)
        print(f"[bootstrap] Applied statement {index}/{len(statements)}")

    print("[bootstrap] Schema bootstrap complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())