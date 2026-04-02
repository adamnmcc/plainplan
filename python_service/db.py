from __future__ import annotations

from functools import lru_cache
from typing import Any

import boto3
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .config import get_settings


@lru_cache(maxsize=1)
def get_pool() -> ConnectionPool:
    settings = get_settings()
    return ConnectionPool(
        conninfo=settings.database_url,
        min_size=1,
        max_size=5,
        timeout=10.0,
        kwargs={"row_factory": dict_row},
    )


@lru_cache(maxsize=1)
def get_rds_data_client() -> Any:
    settings = get_settings()
    return boto3.client("rds-data", region_name=settings.aws_region)


def _query_backend() -> str:
    return get_settings().db_backend


def _parameter_value(value: Any) -> dict[str, Any]:
    if value is None:
        return {"isNull": True}
    if isinstance(value, bool):
        return {"booleanValue": value}
    if isinstance(value, int):
        return {"longValue": value}
    if isinstance(value, float):
        return {"doubleValue": value}
    return {"stringValue": str(value)}


def _convert_sql(query: str, params: tuple[Any, ...]) -> tuple[str, list[dict[str, Any]]]:
    sql = query
    data_api_params: list[dict[str, Any]] = []
    for index, value in enumerate(params, start=1):
        placeholder = f":p{index}"
        sql = sql.replace("%s", placeholder, 1)
        data_api_params.append({"name": f"p{index}", "value": _parameter_value(value)})
    return sql, data_api_params


def _field_value(field: dict[str, Any]) -> Any:
    if field.get("isNull"):
        return None
    for key in ("stringValue", "longValue", "doubleValue", "booleanValue"):
        if key in field:
            return field[key]
    if "arrayValue" in field:
        return field["arrayValue"]
    return None


def _data_api_execute(query: str, params: tuple[Any, ...] = ()) -> dict[str, Any]:
    settings = get_settings()
    sql, data_api_params = _convert_sql(query, params)
    client = get_rds_data_client()
    return client.execute_statement(
        resourceArn=settings.rds_cluster_arn,
        secretArn=settings.rds_secret_arn,
        database=settings.rds_database_name,
        sql=sql,
        parameters=data_api_params,
        includeResultMetadata=True,
    )


def _records_to_rows(result: dict[str, Any]) -> list[dict[str, Any]]:
    metadata = result.get("columnMetadata", [])
    column_names = [column.get("label") or column.get("name") or f"col_{index}" for index, column in enumerate(metadata)]
    rows: list[dict[str, Any]] = []
    for record in result.get("records", []):
        row = {column_names[index]: _field_value(field) for index, field in enumerate(record)}
        rows.append(row)
    return rows


def fetch_one(query: str, params: tuple[Any, ...] = ()) -> dict[str, Any] | None:
    if _query_backend() == "rds_data_api":
        rows = _records_to_rows(_data_api_execute(query, params))
        return rows[0] if rows else None

    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(query, params)
            return cur.fetchone()


def fetch_all(query: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    if _query_backend() == "rds_data_api":
        return _records_to_rows(_data_api_execute(query, params))

    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(query, params)
            return list(cur.fetchall())


def execute(query: str, params: tuple[Any, ...] = ()) -> None:
    if _query_backend() == "rds_data_api":
        _data_api_execute(query, params)
        return

    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(query, params)
