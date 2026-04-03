/**
 * API Key Management Routes
 */
const express = require('express');
const { generateApiKey, hashKey } = require('../middleware/auth');

function createKeysRouter(pool) {
  const router = express.Router();

  router.post('/', async (req, res) => {
    try {
      const { email, name } = req.body || {};
      if (!email || typeof email !== 'string') {
        return res.status(400).json({ success: false, error: 'INVALID_INPUT', message: 'Email is required' });
      }
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(email)) {
        return res.status(400).json({ success: false, error: 'INVALID_INPUT', message: 'Invalid email format' });
      }
      let userResult = await pool.query('SELECT id FROM users WHERE LOWER(email) = LOWER($1)', [email]);
      let userId;
      if (userResult.rows.length === 0) {
        const insertResult = await pool.query('INSERT INTO users (email, name) VALUES ($1, $2) RETURNING id', [email.toLowerCase(), name || null]);
        userId = insertResult.rows[0].id;
      } else {
        userId = userResult.rows[0].id;
      }
      const keyCount = await pool.query('SELECT COUNT(*) as count FROM api_keys WHERE user_id = $1 AND is_active = true', [userId]);
      if (parseInt(keyCount.rows[0].count) >= 5) {
        return res.status(400).json({ success: false, error: 'KEY_LIMIT', message: 'Maximum 5 active API keys per account.' });
      }
      const { key, keyHash, keyPrefix } = generateApiKey();
      const keyName = (name || 'default').slice(0, 255);
      await pool.query('INSERT INTO api_keys (key_hash, key_prefix, user_id, email, name) VALUES ($1, $2, $3, $4, $5)', [keyHash, keyPrefix, userId, email.toLowerCase(), keyName]);
      res.status(201).json({ success: true, api_key: key, key_prefix: keyPrefix, message: 'Store this key securely — it cannot be retrieved later.', dashboard_url: `https://dev.plainplan.click/dashboard?key=${key}` });
    } catch (err) {
      console.error('Key generation error:', err.message);
      res.status(500).json({ success: false, error: 'KEY_GENERATION_FAILED', message: 'Failed to generate API key' });
    }
  });

  router.get('/verify', async (req, res) => {
    const authHeader = req.headers.authorization;
    if (!authHeader) return res.status(401).json({ success: false, valid: false, message: 'No API key provided' });
    const parts = authHeader.split(' ');
    const key = parts.length === 2 ? parts[1] : parts[0];
    if (!key || !key.startsWith('pp_live_')) return res.status(401).json({ success: false, valid: false, message: 'Invalid key format' });
    const keyHash = hashKey(key);
    const result = await pool.query('SELECT id, email, name, is_active, rate_limit_per_minute, rate_limit_per_day, created_at, last_used_at FROM api_keys WHERE key_hash = $1', [keyHash]);
    if (result.rows.length === 0 || !result.rows[0].is_active) return res.status(401).json({ success: false, valid: false, message: 'Invalid or inactive key' });
    const apiKey = result.rows[0];
    res.json({ success: true, valid: true, key: { name: apiKey.name, email: apiKey.email, created_at: apiKey.created_at, last_used_at: apiKey.last_used_at, limits: { per_minute: apiKey.rate_limit_per_minute, per_day: apiKey.rate_limit_per_day } } });
  });

  return router;
}

module.exports = { createKeysRouter };
