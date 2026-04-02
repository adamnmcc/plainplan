from __future__ import annotations

from dataclasses import dataclass
from typing import Any


CRITICAL_RESOURCE_TYPES = {
    "aws_db_instance", "aws_rds_cluster", "aws_dynamodb_table",
    "google_sql_database_instance", "azurerm_mssql_database",
    "aws_s3_bucket", "google_storage_bucket", "azurerm_storage_account",
    "aws_vpc", "google_compute_network", "azurerm_virtual_network",
    "aws_iam_role", "aws_iam_policy", "aws_iam_user",
    "google_project_iam_member", "azurerm_role_assignment",
    "aws_kms_key", "google_kms_crypto_key",
    "aws_route53_zone", "google_dns_managed_zone",
    "aws_elasticache_cluster", "aws_elasticsearch_domain",
    "aws_efs_file_system", "aws_ebs_volume",
}

SECURITY_RESOURCE_TYPES = {
    "aws_security_group", "aws_security_group_rule",
    "aws_network_acl", "aws_network_acl_rule",
    "google_compute_firewall", "azurerm_network_security_group",
    "azurerm_network_security_rule",
    "aws_iam_role", "aws_iam_policy", "aws_iam_role_policy",
    "aws_iam_role_policy_attachment", "aws_iam_user_policy",
    "aws_iam_group_policy", "aws_iam_policy_document",
    "google_project_iam_member", "google_project_iam_binding",
    "azurerm_role_assignment",
}

DANGEROUS_PATTERNS = [
    {"pattern": "0.0.0.0/0", "message": "Wide-open CIDR block (0.0.0.0/0) allows access from anywhere"},
    {"pattern": "::/0", "message": "Wide-open IPv6 CIDR block (::/0) allows access from anywhere"},
    {"pattern": "*", "field": "actions", "message": "Wildcard IAM action (*) grants unrestricted permissions"},
    {"pattern": "false", "field": "encrypted", "message": "Encryption is being disabled"},
    {"pattern": "false", "field": "encryption_at_rest", "message": "Encryption at rest is being disabled"},
]


class PlanParseError(Exception):
    pass


@dataclass
class ParsedPlan:
    changes: list[dict[str, Any]]
    risk_flags: list[dict[str, Any]]
    metadata: dict[str, Any]


def parse_plan(plan_json: dict[str, Any]) -> ParsedPlan:
    if not isinstance(plan_json, dict):
        raise PlanParseError("Plan must be a JSON object")

    resource_changes = plan_json.get("resource_changes")
    if resource_changes is None:
        if plan_json.get("values", {}).get("root_module"):
            raise PlanParseError("This looks like a Terraform state file, not a plan. Run: terraform show -json tfplan")
        if "configuration" in plan_json:
            raise PlanParseError("This looks like a Terraform config, not a plan. Run: terraform plan -out=tfplan && terraform show -json tfplan")
        raise PlanParseError("No resource_changes found. Expected output from: terraform show -json tfplan")

    if not isinstance(resource_changes, list):
        raise PlanParseError("resource_changes must be an array")

    changes: list[dict[str, Any]] = []
    counts = {"create": 0, "update": 0, "destroy": 0, "replace": 0, "noop": 0}

    for rc in resource_changes:
        actions = (rc.get("change") or {}).get("actions") or []
        action = classify_action(actions)
        if action in {"no-op", "read"}:
            counts["noop"] += 1
            continue

        counts[action] += 1
        change = {
            "address": rc.get("address") or "unknown",
            "type": rc.get("type") or "unknown",
            "name": rc.get("name") or "unknown",
            "provider": simplify_provider(rc.get("provider_name")),
            "action": action,
            "before": (rc.get("change") or {}).get("before"),
            "after": (rc.get("change") or {}).get("after"),
            "after_unknown": (rc.get("change") or {}).get("after_unknown"),
        }
        if action == "update" and change["before"] is not None and change["after"] is not None:
            change["changed_fields"] = get_changed_fields(change["before"], change["after"])
        changes.append(change)

    risk_flags = detect_risks(changes)
    metadata = {
        "terraform_version": plan_json.get("terraform_version", "unknown"),
        "format_version": plan_json.get("format_version", "unknown"),
        "resources_total": len(changes),
        "resources_created": counts["create"],
        "resources_updated": counts["update"],
        "resources_destroyed": counts["destroy"],
        "resources_replaced": counts["replace"],
        "resources_unchanged": counts["noop"],
    }

    severity_order = {"HIGH": 3, "MED": 2, "LOW": 1}
    max_risk = "LOW"
    for flag in risk_flags:
        if severity_order.get(flag.get("severity", "LOW"), 0) > severity_order.get(max_risk, 0):
            max_risk = flag["severity"]

    metadata["max_risk_level"] = max_risk
    return ParsedPlan(changes=changes, risk_flags=risk_flags, metadata=metadata)


def classify_action(actions: list[str]) -> str:
    if "delete" in actions and "create" in actions:
        return "replace"
    if actions == ["create"]:
        return "create"
    if "update" in actions:
        return "update"
    if actions == ["delete"]:
        return "destroy"
    if "no-op" in actions:
        return "no-op"
    if "read" in actions:
        return "read"
    return actions[0] if actions else "no-op"


def simplify_provider(provider: str | None) -> str:
    if not provider:
        return "unknown"
    return provider.split("/")[-1]


def get_changed_fields(before: dict[str, Any], after: dict[str, Any]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    keys = set(before.keys()) | set(after.keys())
    for key in keys:
        before_val = before.get(key)
        after_val = after.get(key)
        if before_val != after_val:
            out.append({"field": key, "from": summarize_value(before_val), "to": summarize_value(after_val)})
    return out


def summarize_value(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, str):
        return value if len(value) <= 100 else value[:97] + "..."
    if isinstance(value, (int, float, bool)):
        return value
    if isinstance(value, list):
        return f"[{len(value)} items]"
    if isinstance(value, dict):
        return f"{{{len(value)} fields}}"
    return str(value)


def detect_risks(changes: list[dict[str, Any]]) -> list[dict[str, str]]:
    flags: list[dict[str, str]] = []

    for change in changes:
        action = change["action"]
        resource_type = change["type"]
        address = change["address"]

        if action == "destroy":
            high = resource_type in CRITICAL_RESOURCE_TYPES
            flags.append({
                "severity": "HIGH" if high else "MED",
                "resource": address,
                "message": f"{resource_type} is being destroyed" + (
                    " — this is a critical resource that may contain data" if high else ""
                ),
            })

        if action == "replace":
            flags.append({
                "severity": "HIGH" if resource_type in CRITICAL_RESOURCE_TYPES else "MED",
                "resource": address,
                "message": f"{resource_type} is being replaced (destroyed and recreated) — may cause downtime or data loss",
            })

        if resource_type in SECURITY_RESOURCE_TYPES and action in {"create", "update"}:
            flags.append({
                "severity": "MED",
                "resource": address,
                "message": f"Security-related resource {resource_type} is being {'created' if action == 'create' else 'modified'}",
            })

        after = change.get("after")
        if isinstance(after, dict):
            check_dangerous_values(after, address, flags)

    order = {"HIGH": 0, "MED": 1, "LOW": 2}
    return sorted(flags, key=lambda x: order.get(x.get("severity", "LOW"), 99))


def check_dangerous_values(obj: Any, resource_address: str, flags: list[dict[str, str]], depth: int = 0) -> None:
    if depth > 5 or not isinstance(obj, dict):
        return

    for key, value in obj.items():
        if isinstance(value, str):
            for dp in DANGEROUS_PATTERNS:
                if dp.get("field") and dp["field"] != key:
                    continue
                if dp["pattern"] in value:
                    flags.append({"severity": "HIGH", "resource": resource_address, "message": f"{dp['message']} (field: {key})"})
        elif isinstance(value, list):
            for item in value:
                if isinstance(item, dict):
                    check_dangerous_values(item, resource_address, flags, depth + 1)
                elif isinstance(item, str):
                    for dp in DANGEROUS_PATTERNS:
                        if dp["pattern"] in item:
                            flags.append({"severity": "HIGH", "resource": resource_address, "message": dp["message"]})
        elif isinstance(value, dict):
            check_dangerous_values(value, resource_address, flags, depth + 1)
