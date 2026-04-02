module.exports = {
  name: 'api_requests_table',
  up: async (client) => {
    // Granular request log for usage metrics, early adopter detection, and error tracking
    await client.query(`
      CREATE TABLE IF NOT EXISTS api_requests (
        id SERIAL PRIMARY KEY,
        api_key_hash VARCHAR(64),
        request_size_bytes INTEGER,
        response_time_ms INTEGER,
        risk_level VARCHAR(20),
        resource_count INTEGER,
        error TEXT,
        created_at TIMESTAMP DEFAULT NOW()
      )
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_api_requests_created_at ON api_requests (created_at DESC)
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_api_requests_api_key_hash ON api_requests (api_key_hash)
    `);
  }
};
