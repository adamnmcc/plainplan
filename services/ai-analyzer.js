/**
 * AI-Powered Terraform Plan Analyzer
 *
 * Uses an OpenRouter-compatible API client to generate
 * human-readable analysis from parsed Terraform plan data.
 */
const OpenAI = require('openai');

let client = null;

function getClient() {
  if (!client) {
    client = new OpenAI({
      apiKey: process.env.OPENROUTER_API_KEY || process.env.OPENAI_API_KEY,
      baseURL: process.env.OPENROUTER_BASE_URL || process.env.OPENAI_BASE_URL || 'https://openrouter.ai/api/v1',
    });
  }
  return client;
}

async function analyzePlan(parsedPlan) {
  const { changes, riskFlags, metadata } = parsedPlan;

  const changesSummary = changes.map(c => {
    const parts = [`${c.action.toUpperCase()}: ${c.address} (${c.provider})`];
    if (c.changedFields && c.changedFields.length > 0) {
      const fieldChanges = c.changedFields.slice(0, 8).map(f => `  - ${f.field}: ${f.from ?? 'null'} → ${f.to ?? 'null'}`);
      parts.push(fieldChanges.join('\n'));
      if (c.changedFields.length > 8) parts.push(`  ... and ${c.changedFields.length - 8} more fields`);
    }
    return parts.join('\n');
  }).join('\n\n');

  const heuristicFlags = riskFlags.map(f => `[${f.severity}] ${f.resource}: ${f.message}`).join('\n');
  const prompt = buildPrompt(changesSummary, heuristicFlags, metadata);

  const ai = getClient();
  const startTime = Date.now();

  const response = await ai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: prompt },
    ],
    temperature: 0.3,
    max_tokens: 4000,
    response_format: { type: 'json_object' },
  });

  const processingTime = Date.now() - startTime;
  const content = response.choices?.[0]?.message?.content;
  const tokensUsed = response.usage?.total_tokens || 0;

  if (!content) throw new Error('AI returned empty response');

  let analysis;
  try { analysis = JSON.parse(content); }
  catch (e) { throw new Error('AI returned invalid JSON: ' + e.message); }

  const allRiskFlags = mergeRiskFlags(riskFlags, analysis.risk_flags || []);
  const prMarkdown = generatePRMarkdown(analysis.summary, allRiskFlags, analysis.reviewer_checklist || [], metadata);

  return {
    summary: analysis.summary || 'No summary generated',
    risk_flags: allRiskFlags,
    reviewer_checklist: analysis.reviewer_checklist || [],
    pr_markdown: prMarkdown,
    _ai_metadata: { processing_time_ms: processingTime, tokens_used: tokensUsed },
  };
}

const SYSTEM_PROMPT = `You are PlanPlain, an expert Terraform/OpenTofu infrastructure analyst. Your job is to make infrastructure changes understandable to any engineer, not just Terraform experts.

You analyze infrastructure plan changes and produce clear, actionable output. Be specific — reference actual resource names and values. Don't be vague.

IMPORTANT: Respond with valid JSON only. No markdown wrapping.`;

function buildPrompt(changesSummary, heuristicFlags, metadata) {
  return `Analyze this Terraform plan and respond with JSON containing exactly these fields:

{
  "summary": "2-4 sentence plain-English summary of what's changing and why it matters.",
  "risk_flags": [
    { "severity": "HIGH|MED|LOW", "resource": "resource.address", "message": "Why this is risky" }
  ],
  "reviewer_checklist": [
    "Specific, actionable item a reviewer should verify"
  ]
}

## Plan Overview
- Terraform version: ${metadata.terraform_version}
- Resources created: ${metadata.resources_created}
- Resources updated: ${metadata.resources_updated}
- Resources destroyed: ${metadata.resources_destroyed}
- Resources replaced: ${metadata.resources_replaced}
- Total changes: ${metadata.resources_total}

## Resource Changes
${changesSummary || 'No changes detected'}

## Detected Risk Patterns
${heuristicFlags || 'None detected by heuristics'}

Rules:
- For risk_flags: Only add flags the heuristics missed. Don't duplicate the detected patterns above.
- For reviewer_checklist: 3-8 specific items. Include "Confirm this plan was generated from the correct branch/workspace" as the last item.
- Be direct. No corporate speak.`;
}

function mergeRiskFlags(heuristicFlags, aiFlags) {
  const merged = [...heuristicFlags];
  const existingResources = new Set(heuristicFlags.map(f => `${f.resource}:${f.severity}`));
  for (const flag of aiFlags) {
    const key = `${flag.resource}:${flag.severity}`;
    if (!existingResources.has(key)) { merged.push(flag); existingResources.add(key); }
  }
  const order = { HIGH: 0, MED: 1, LOW: 2 };
  merged.sort((a, b) => (order[a.severity] || 99) - (order[b.severity] || 99));
  return merged;
}

function generatePRMarkdown(summary, riskFlags, checklist, metadata) {
  const lines = [];
  lines.push('## Terraform Plan Analysis');
  lines.push('');
  lines.push(`> Analyzed by [PlanPlain](https://dev.api.plainplan.click) | ${metadata.resources_total} resource(s) changing`);
  lines.push('');
  lines.push('### Summary');
  lines.push('');
  lines.push(summary);
  lines.push('');
  lines.push('### Changes');
  lines.push('');
  lines.push('| Action | Count |');
  lines.push('|--------|-------|');
  if (metadata.resources_created > 0) lines.push(`| :green_circle: Create | ${metadata.resources_created} |`);
  if (metadata.resources_updated > 0) lines.push(`| :yellow_circle: Update | ${metadata.resources_updated} |`);
  if (metadata.resources_destroyed > 0) lines.push(`| :red_circle: Destroy | ${metadata.resources_destroyed} |`);
  if (metadata.resources_replaced > 0) lines.push(`| :orange_circle: Replace | ${metadata.resources_replaced} |`);
  lines.push('');
  if (riskFlags.length > 0) {
    lines.push(`### Risk Flags ${riskFlags.some(f => f.severity === 'HIGH') ? ':rotating_light:' : ':warning:'}`);
    lines.push('');
    for (const flag of riskFlags) {
      const icon = flag.severity === 'HIGH' ? ':red_circle:' : flag.severity === 'MED' ? ':yellow_circle:' : ':white_circle:';
      lines.push(`- ${icon} **${flag.severity}** \`${flag.resource}\`: ${flag.message}`);
    }
    lines.push('');
  }
  if (checklist.length > 0) {
    lines.push('### Reviewer Checklist');
    lines.push('');
    for (const item of checklist) lines.push(`- [ ] ${item}`);
    lines.push('');
  }
  lines.push('---');
  lines.push('*Generated by [PlanPlain](https://dev.api.plainplan.click)*');
  return lines.join('\n');
}

module.exports = { analyzePlan };
