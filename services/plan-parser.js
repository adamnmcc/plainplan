/**
 * Terraform Plan Parser
 *
 * Extracts structured data from Terraform plan JSON (terraform show -json tfplan)
 * and detects known risk patterns using heuristics.
 */

const CRITICAL_RESOURCE_TYPES = new Set([
  'aws_db_instance', 'aws_rds_cluster', 'aws_dynamodb_table',
  'google_sql_database_instance', 'azurerm_mssql_database',
  'aws_s3_bucket', 'google_storage_bucket', 'azurerm_storage_account',
  'aws_vpc', 'google_compute_network', 'azurerm_virtual_network',
  'aws_iam_role', 'aws_iam_policy', 'aws_iam_user',
  'google_project_iam_member', 'azurerm_role_assignment',
  'aws_kms_key', 'google_kms_crypto_key',
  'aws_route53_zone', 'google_dns_managed_zone',
  'aws_elasticache_cluster', 'aws_elasticsearch_domain',
  'aws_efs_file_system', 'aws_ebs_volume',
]);

const SECURITY_RESOURCE_TYPES = new Set([
  'aws_security_group', 'aws_security_group_rule',
  'aws_network_acl', 'aws_network_acl_rule',
  'google_compute_firewall', 'azurerm_network_security_group',
  'azurerm_network_security_rule',
  'aws_iam_role', 'aws_iam_policy', 'aws_iam_role_policy',
  'aws_iam_role_policy_attachment', 'aws_iam_user_policy',
  'aws_iam_group_policy', 'aws_iam_policy_document',
  'google_project_iam_member', 'google_project_iam_binding',
  'azurerm_role_assignment',
]);

const DANGEROUS_PATTERNS = [
  { pattern: '0.0.0.0/0', message: 'Wide-open CIDR block (0.0.0.0/0) allows access from anywhere' },
  { pattern: '::/0', message: 'Wide-open IPv6 CIDR block (::/0) allows access from anywhere' },
  { pattern: '*', field: 'actions', message: 'Wildcard IAM action (*) grants unrestricted permissions' },
  { pattern: 'false', field: 'encrypted', message: 'Encryption is being disabled' },
  { pattern: 'false', field: 'encryption_at_rest', message: 'Encryption at rest is being disabled' },
];

function parsePlan(planJson) {
  if (!planJson || typeof planJson !== 'object') throw new PlanParseError('Plan must be a JSON object');
  const resourceChanges = planJson.resource_changes;
  if (!resourceChanges) {
    if (planJson.values && planJson.values.root_module) throw new PlanParseError('This looks like a Terraform state file, not a plan. Run: terraform show -json tfplan');
    if (planJson.configuration) throw new PlanParseError('This looks like a Terraform config, not a plan. Run: terraform plan -out=tfplan && terraform show -json tfplan');
    throw new PlanParseError('No resource_changes found. Expected output from: terraform show -json tfplan');
  }
  if (!Array.isArray(resourceChanges)) throw new PlanParseError('resource_changes must be an array');

  const changes = [];
  const counts = { create: 0, update: 0, destroy: 0, replace: 0, noop: 0 };

  for (const rc of resourceChanges) {
    const actions = rc.change?.actions || [];
    const action = classifyAction(actions);
    if (action === 'no-op' || action === 'read') { counts.noop++; continue; }
    counts[action]++;
    const change = {
      address: rc.address || 'unknown', type: rc.type || 'unknown', name: rc.name || 'unknown',
      provider: simplifyProvider(rc.provider_name), action,
      before: rc.change?.before || null, after: rc.change?.after || null, afterUnknown: rc.change?.after_unknown || null,
    };
    if (action === 'update' && change.before && change.after) change.changedFields = getChangedFields(change.before, change.after);
    changes.push(change);
  }

  const riskFlags = detectRisks(changes);
  const metadata = {
    terraform_version: planJson.terraform_version || 'unknown',
    format_version: planJson.format_version || 'unknown',
    resources_total: changes.length,
    resources_created: counts.create, resources_updated: counts.update,
    resources_destroyed: counts.destroy, resources_replaced: counts.replace, resources_unchanged: counts.noop,
  };
  const maxRisk = riskFlags.length > 0
    ? riskFlags.reduce((max, f) => { const order = { HIGH: 3, MED: 2, LOW: 1 }; return (order[f.severity] || 0) > (order[max] || 0) ? f.severity : max; }, 'LOW')
    : 'LOW';
  return { changes, riskFlags, metadata: { ...metadata, max_risk_level: maxRisk } };
}

function classifyAction(actions) {
  if (actions.includes('delete') && actions.includes('create')) return 'replace';
  if (actions.includes('create') && actions.length === 1) return 'create';
  if (actions.includes('update')) return 'update';
  if (actions.includes('delete') && actions.length === 1) return 'destroy';
  if (actions.includes('no-op')) return 'no-op';
  if (actions.includes('read')) return 'read';
  return actions[0] || 'no-op';
}

function simplifyProvider(provider) {
  if (!provider) return 'unknown';
  const parts = provider.split('/');
  return parts[parts.length - 1] || provider;
}

function getChangedFields(before, after) {
  const changed = [];
  const allKeys = new Set([...Object.keys(before || {}), ...Object.keys(after || {})]);
  for (const key of allKeys) {
    const beforeVal = before?.[key]; const afterVal = after?.[key];
    if (JSON.stringify(beforeVal) !== JSON.stringify(afterVal)) changed.push({ field: key, from: summarizeValue(beforeVal), to: summarizeValue(afterVal) });
  }
  return changed;
}

function summarizeValue(val) {
  if (val === null || val === undefined) return null;
  if (typeof val === 'string') return val.length > 100 ? val.slice(0, 97) + '...' : val;
  if (typeof val === 'number' || typeof val === 'boolean') return val;
  if (Array.isArray(val)) return `[${val.length} items]`;
  if (typeof val === 'object') return `{${Object.keys(val).length} fields}`;
  return String(val);
}

function detectRisks(changes) {
  const flags = [];
  for (const change of changes) {
    if (change.action === 'destroy') {
      flags.push({ severity: CRITICAL_RESOURCE_TYPES.has(change.type) ? 'HIGH' : 'MED', resource: change.address, message: `${change.type} is being destroyed${CRITICAL_RESOURCE_TYPES.has(change.type) ? ' — this is a critical resource that may contain data' : ''}` });
    }
    if (change.action === 'replace') {
      flags.push({ severity: CRITICAL_RESOURCE_TYPES.has(change.type) ? 'HIGH' : 'MED', resource: change.address, message: `${change.type} is being replaced (destroyed and recreated) — may cause downtime or data loss` });
    }
    if (SECURITY_RESOURCE_TYPES.has(change.type) && (change.action === 'create' || change.action === 'update')) {
      flags.push({ severity: 'MED', resource: change.address, message: `Security-related resource ${change.type} is being ${change.action === 'create' ? 'created' : 'modified'}` });
    }
    if (change.after) checkDangerousValues(change.after, change.address, flags);
  }
  const severityOrder = { HIGH: 0, MED: 1, LOW: 2 };
  flags.sort((a, b) => (severityOrder[a.severity] || 99) - (severityOrder[b.severity] || 99));
  return flags;
}

function checkDangerousValues(obj, resourceAddress, flags, depth = 0) {
  if (depth > 5 || !obj || typeof obj !== 'object') return;
  for (const [key, value] of Object.entries(obj)) {
    if (typeof value === 'string') {
      for (const dp of DANGEROUS_PATTERNS) {
        if (dp.field && dp.field !== key) continue;
        if (value.includes(dp.pattern)) flags.push({ severity: 'HIGH', resource: resourceAddress, message: `${dp.message} (field: ${key})` });
      }
    } else if (Array.isArray(value)) {
      for (const item of value) {
        if (typeof item === 'object') checkDangerousValues(item, resourceAddress, flags, depth + 1);
        else if (typeof item === 'string') {
          for (const dp of DANGEROUS_PATTERNS) { if (item.includes(dp.pattern)) flags.push({ severity: 'HIGH', resource: resourceAddress, message: dp.message }); }
        }
      }
    } else if (typeof value === 'object') checkDangerousValues(value, resourceAddress, flags, depth + 1);
  }
}

class PlanParseError extends Error {
  constructor(message) { super(message); this.name = 'PlanParseError'; }
}

module.exports = { parsePlan, PlanParseError };
