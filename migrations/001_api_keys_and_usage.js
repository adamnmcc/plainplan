module.exports = {
  name: 'api_keys_and_usage',
  up: async (client) => {
    // API keys for authenticating /analyze requests
    await client.query(`
      CREATE TABLE IF NOT EXISTS api_keys (
        id SERIAL PRIMARY KEY,
        key_hash VARCHAR(64) NOT NULL UNIQUE,
        key_prefix VARCHAR(12) NOT NULL,
        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        email VARCHAR(255) NOT NULL,
        name VARCHAR(255) DEFAULT 'default',
        created_at TIMESTAMPTZ DEFAULT NOW(),
        last_used_at TIMESTAMPTZ,
        is_active BOOLEAN DEFAULT true,
        rate_limit_per_minute INTEGER DEFAULT 10,
        rate_limit_per_day INTEGER DEFAULT 200
      )
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_api_keys_key_hash ON api_keys (key_hash)
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_api_keys_email ON api_keys (LOWER(email))
    `);

    // Log every analysis for usage tracking and debugging
    await client.query(`
      CREATE TABLE IF NOT EXISTS analysis_logs (
        id SERIAL PRIMARY KEY,
        api_key_id INTEGER REFERENCES api_keys(id) ON DELETE SET NULL,
        plan_hash VARCHAR(64),
        resources_total INTEGER DEFAULT 0,
        resources_created INTEGER DEFAULT 0,
        resources_updated INTEGER DEFAULT 0,
        resources_destroyed INTEGER DEFAULT 0,
        resources_replaced INTEGER DEFAULT 0,
        max_risk_level VARCHAR(10),
        processing_time_ms INTEGER,
        ai_tokens_used INTEGER DEFAULT 0,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_analysis_logs_api_key ON analysis_logs (api_key_id, created_at DESC)
    `);
  }
};
