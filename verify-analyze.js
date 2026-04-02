/**
 * Verify the /analyze endpoint works end-to-end
 */
const BASE = process.env.BASE_URL || 'http://localhost:3000';

async function test(name, fn) {
  try { await fn(); console.log(`  PASS: ${name}`); return true; }
  catch (err) { console.error(`  FAIL: ${name} — ${err.message}`); return false; }
}
function assert(condition, message) { if (!condition) throw new Error(message); }

async function run() {
  console.log(`\nTesting PlanPlain API at ${BASE}\n`);
  let apiKey = null, passed = 0, failed = 0;
  const track = (result) => result ? passed++ : failed++;

  track(await test('GET /health', async () => {
    const res = await fetch(`${BASE}/health`); assert(res.ok, `Status ${res.status}`);
    const data = await res.json(); assert(data.status === 'healthy', `Unexpected: ${JSON.stringify(data)}`);
  }));

  track(await test('GET /api', async () => {
    const res = await fetch(`${BASE}/api`); assert(res.ok, `Status ${res.status}`);
    const data = await res.json(); assert(data.name === 'PlanPlain API', `Unexpected name: ${data.name}`);
  }));

  track(await test('GET /api/example', async () => {
    const res = await fetch(`${BASE}/api/example`); assert(res.ok, `Status ${res.status}`);
    const data = await res.json(); assert(data.plan, 'Missing plan'); assert(data.plan.resource_changes, 'Missing resource_changes');
  }));

  track(await test('POST /api/keys — generate key', async () => {
    const res = await fetch(`${BASE}/api/keys`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: 'test@planplain.dev', name: 'verify-script' }) });
    assert(res.status === 201, `Status ${res.status}: ${await res.text()}`);
    const data = await res.json(); assert(data.success, 'Not successful'); assert(data.api_key?.startsWith('pp_live_'), `Bad key format: ${data.api_key}`);
    apiKey = data.api_key; console.log(`    Key prefix: ${data.key_prefix}`);
  }));

  track(await test('GET /api/keys/verify', async () => {
    const res = await fetch(`${BASE}/api/keys/verify`, { headers: { 'Authorization': `Bearer ${apiKey}` } });
    assert(res.ok, `Status ${res.status}`); const data = await res.json(); assert(data.valid === true, 'Key not valid');
  }));

  track(await test('POST /api/analyze — no auth → 401', async () => {
    const res = await fetch(`${BASE}/api/analyze`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) });
    assert(res.status === 401, `Expected 401, got ${res.status}`);
  }));

  track(await test('POST /api/analyze — empty body → 400', async () => {
    const res = await fetch(`${BASE}/api/analyze`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${apiKey}` }, body: JSON.stringify({}) });
    assert(res.status === 422 || res.status === 400, `Expected 400/422, got ${res.status}`);
  }));

  track(await test('POST /api/analyze — sample plan → full analysis', async () => {
    const exampleRes = await fetch(`${BASE}/api/example`);
    const { plan } = await exampleRes.json();
    const res = await fetch(`${BASE}/api/analyze`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${apiKey}` }, body: JSON.stringify(plan) });
    assert(res.ok, `Status ${res.status}: ${await res.text()}`);
    const data = await res.json(); assert(data.success, 'Analysis not successful'); assert(data.analysis, 'Missing analysis');
    assert(typeof data.analysis.summary === 'string', 'Missing summary');
    assert(Array.isArray(data.analysis.risk_flags), 'Missing risk_flags');
    console.log(`    Summary: ${data.analysis.summary.slice(0, 100)}...`);
    console.log(`    Risk flags: ${data.analysis.risk_flags.length}`);
    console.log(`    Resources: ${data.metadata.resources_total} total`);
  }));

  console.log(`\n${'='.repeat(40)}\nResults: ${passed} passed, ${failed} failed\n${'='.repeat(40)}\n`);
  process.exit(failed > 0 ? 1 : 0);
}

run().catch(err => { console.error('Test runner failed:', err); process.exit(1); });
