"""Apply schema.sql to a PostgreSQL database via direct connection (psycopg)."""
from __future__ import annotations

import argparse
import re
from pathlib import Path

import psycopg


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Apply schema.sql to PostgreSQL via direct connection")
    parser.add_argument("--database-url", required=True)
    parser.add_argument("--schema-file", required=True)
    return parser.parse_args()


def split_sql(sql_text: str) -> list[str]:
    without_comments = re.sub(r"--.*$", "", sql_text, flags=re.MULTILINE)
    statements = [statement.strip() for statement in without_comments.split(";")]
    return [statement for statement in statements if statement]


def main() -> int:
    args = parse_args()
    schema_path = Path(args.schema_file)
    statements = split_sql(schema_path.read_text(encoding="utf-8"))
    print(f"[bootstrap] Applying {len(statements)} SQL statements via direct connection")

    with psycopg.connect(args.database_url, autocommit=True) as conn:
        for index, statement in enumerate(statements, start=1):
            conn.execute(statement)
            print(f"[bootstrap] Applied statement {index}/{len(statements)}")

    print("[bootstrap] Schema bootstrap complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
