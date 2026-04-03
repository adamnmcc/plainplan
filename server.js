const express = require('express');
const { Pool } = require('pg');
const path = require('path');
const fs = require('fs');

const app = express();
const port = process.env.PORT || 3000;

if (!process.env.DATABASE_URL) {
  console.error('ERROR: DATABASE_URL environment variable is required');
  process.exit(1);
}

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL.includes('localhost') ? false : { rejectUnauthorized: false }
});

app.use(express.json({ limit: '10mb' }));

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

const { authenticateApiKey, hashKey } = require('./middleware/auth');
const { rateLimit } = require('./middleware/rate-limit');
const { createKeysRouter } = require('./routes/keys');
const { createAnalyzeRouter, logApiRequest } = require('./routes/analyze');

app.use('/api/keys', createKeysRouter(pool));
app.use('/api/analyze', authenticateApiKey(pool), rateLimit(), createAnalyzeRouter(pool));

app.get('/api', (req, res) => {
  res.json({
    name: 'PlanPlain API',
    version: '1.0.0',
    description: 'Terraform plan analysis made simple',
    endpoints: {
      'POST /api/keys': { description: 'Generate an API key', auth: 'none' },
      'GET /api/keys/verify': { description: 'Verify an API key', auth: 'Bearer pp_live_xxxxx' },
      'POST /api/analyze': { description: 'Analyze a Terraform plan', auth: 'Bearer pp_live_xxxxx' },
      'GET /api/example': { description: 'Get a sample plan for testing', auth: 'none' },
    },
  });
});

app.get('/api/example', (req, res) => {
  const samplePath = path.join(__dirname, 'test-fixtures', 'sample-plan.json');
  try {
    const sample = JSON.parse(fs.readFileSync(samplePath, 'utf8'));
    res.json({ description: 'Sample Terraform plan for testing', plan: sample });
  } catch (err) {
    res.status(500).json({ error: 'Sample plan not found' });
  }
});

app.get('/api/stats', async (req, res) => {
  const secret = process.env.STATS_SECRET;
  if (!secret) return res.status(503).json({ success: false, error: 'Stats not configured' });
  const provided = (req.headers.authorization || '').replace('Bearer ', '');
  if (provided !== secret) return res.status(401).json({ success: false, error: 'Unauthorized' });

  try {
    const result = await pool.query(`
      SELECT
        COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '24 hours') AS requests_24h,
        COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days')   AS requests_7d,
        COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '30 days')  AS requests_30d,
        COUNT(*) AS total_requests,
        COUNT(DISTINCT api_key_hash) FILTER (WHERE api_key_hash IS NOT NULL) AS unique_keys_total,
        ROUND(AVG(response_time_ms)) AS avg_response_time_ms,
        COUNT(*) FILTER (WHERE error IS NOT NULL) AS total_errors
      FROM api_requests
    `);
    const row = result.rows[0];
    res.json({
      success: true,
      stats: {
        requests: {
          last_24h: parseInt(row.requests_24h, 10),
          last_7d: parseInt(row.requests_7d, 10),
          last_30d: parseInt(row.requests_30d, 10),
          total: parseInt(row.total_requests, 10),
        },
        unique_api_keys: { total: parseInt(row.unique_keys_total, 10) },
        performance: { avg_response_time_ms: parseInt(row.avg_response_time_ms, 10) || 0 },
        errors: { total: parseInt(row.total_errors, 10) },
      },
      generated_at: new Date().toISOString(),
    });
  } catch (err) {
    console.error('Stats endpoint error:', err);
    res.status(500).json({ success: false, error: 'Failed to query stats' });
  }
});

app.get('/api/dashboard', async (req, res) => {
  const rawKey = req.query.key;
  if (!rawKey || !rawKey.startsWith('pp_live_')) {
    return res.status(401).json({ success: false, error: 'INVALID_KEY', message: 'Provide your API key as ?key=pp_live_xxx' });
  }
  const keyHash = hashKey(rawKey);
  try {
    const keyResult = await pool.query(
      'SELECT id, key_prefix, email, name, created_at, last_used_at, rate_limit_per_minute, rate_limit_per_day, is_active FROM api_keys WHERE key_hash = $1',
      [keyHash]
    );
    if (keyResult.rows.length === 0 || !keyResult.rows[0].is_active) {
      return res.status(401).json({ success: false, error: 'KEY_NOT_FOUND', message: 'API key not found or inactive' });
    }
    const keyRow = keyResult.rows[0];
    const usageResult = await pool.query(
      `SELECT COUNT(*) AS total,
         COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours') AS today,
         COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days') AS week,
         COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days') AS month,
         ROUND(AVG(response_time_ms)) AS avg_ms
       FROM api_requests WHERE api_key_hash = $1`,
      [keyHash]
    );
    const u = usageResult.rows[0];
    const dailyUsed = parseInt(u.today, 10) || 0;
    const dailyLimit = keyRow.rate_limit_per_day || 200;
    const minuteLimit = keyRow.rate_limit_per_minute || 10;
    const minuteResult = await pool.query(
      "SELECT COUNT(*) AS cnt FROM api_requests WHERE api_key_hash = $1 AND created_at >= NOW() - INTERVAL '1 minute'",
      [keyHash]
    );
    const minuteUsed = parseInt(minuteResult.rows[0].cnt, 10) || 0;
    const recentResult = await pool.query(
      'SELECT created_at, risk_level, response_time_ms, resource_count, error FROM api_requests WHERE api_key_hash = $1 ORDER BY created_at DESC LIMIT 10',
      [keyHash]
    );
    res.json({
      success: true,
      key: { prefix: keyRow.key_prefix, email: keyRow.email, name: keyRow.name, created_at: keyRow.created_at, last_used_at: keyRow.last_used_at },
      usage: { today: dailyUsed, week: parseInt(u.week, 10) || 0, month: parseInt(u.month, 10) || 0, total: parseInt(u.total, 10) || 0, avg_response_ms: parseInt(u.avg_ms, 10) || 0 },
      rate_limits: { per_minute: minuteLimit, per_day: dailyLimit, used_minute: minuteUsed, used_day: dailyUsed, remaining_minute: Math.max(minuteLimit - minuteUsed, 0), remaining_day: Math.max(dailyLimit - dailyUsed, 0) },
      recent_requests: recentResult.rows.map(r => ({ timestamp: r.created_at, risk_level: r.risk_level || null, response_time_ms: r.response_time_ms || null, resource_count: r.resource_count || null, status: r.error ? 'error' : 'ok', error: r.error || null })),
      generated_at: new Date().toISOString(),
    });
  } catch (err) {
    console.error('[dashboard] error:', err.message);
    res.status(500).json({ success: false, error: 'QUERY_FAILED' });
  }
});

app.get('/dashboard', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'dashboard.html'));
});

app.use(express.static(path.join(__dirname, 'public')));

app.post('/analyze', async (req, res) => {
  const startTime = Date.now();
  const requestSizeBytes = parseInt(req.headers['content-length'] || '0', 10) || Buffer.byteLength(JSON.stringify(req.body || {}));
  try {
    const plan = req.body;
    if (!plan || typeof plan !== 'object') return res.status(400).json({ error: 'Invalid request body' });
    if (!plan.resource_changes || !Array.isArray(plan.resource_changes)) return res.status(400).json({ error: 'Invalid Terraform plan JSON. Expected resource_changes array.' });
    const result = { summary: { total_changes: plan.resource_changes.length }, risk_flags: [], reviewer_checklist: ['Review full plan output'], markdown: '## Terraform Plan\n\n*Generated by PlanPlain*' };
    const processingTime = Date.now() - startTime;
    logApiRequest(pool, { apiKeyHash: null, requestSizeBytes, responseTimeMs: processingTime, riskLevel: 'LOW', resourceCount: plan.resource_changes.length, error: null }).catch(() => {});
    return res.json(result);
  } catch (err) {
    console.error('Analyze error:', err);
    return res.status(500).json({ error: 'Failed to analyze plan' });
  }
});

app.get('/docs', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'docs.html'));
});

app.get('/', (req, res) => {
  const htmlPath = path.join(__dirname, 'public', 'index.html');
  if (fs.existsSync(htmlPath)) {
    res.type('html').sendFile(htmlPath);
  } else {
    res.json({ message: 'PlanPlain API' });
  }
});

app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ success: false, error: 'INTERNAL_ERROR', message: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message });
});

app.listen(port, () => {
  console.log('PlanPlain API running on port ' + port);
});
