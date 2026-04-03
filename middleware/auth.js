/**
 * API Key Authentication Middleware
 *
 * Validates API keys from the Authorization header.
 * Format: Authorization: Bearer pp_live_xxxxx
 */
const crypto = require('crypto');

/**
 * Hash an API key for database lookup
 */
function hashKey(key) {
  return crypto.createHash('sha256').update(key).digest('hex');
}

/**
 * Generate a new API key
 * Returns { key, keyHash, keyPrefix }
 */
function generateApiKey() {
  const random = crypto.randomBytes(24).toString('hex');
  const key = `pp_live_${random}`;
  const keyHash = hashKey(key);
  const keyPrefix = key.slice(0, 12);
  return { key, keyHash, keyPrefix };
}

/**
 * Express middleware to authenticate API key
 * Attaches req.apiKey with the key record from DB
 */
function authenticateApiKey(pool) {
  return async (req, res, next) => {
    // Extract key from Authorization header
    const authHeader = req.headers.authorization;
    if (!authHeader) {
      return res.status(401).json({
        success: false,
        error: 'MISSING_API_KEY',
        message: 'Missing Authorization header. Use: Authorization: Bearer pp_live_xxxxx',
      });
    }

    const parts = authHeader.split(' ');
    const key = parts.length === 2 && parts[0].toLowerCase() === 'bearer'
      ? parts[1]
      : parts[0]; // Support both "Bearer key" and just "key"

    if (!key || !key.startsWith('pp_live_')) {
      return res.status(401).json({
        success: false,
        error: 'INVALID_API_KEY',
        message: 'Invalid API key format. Keys start with pp_live_',
      });
    }

    // Look up key in database
    const keyHash = hashKey(key);
    try {
      const result = await pool.query(
        'SELECT id, email, name, is_active, rate_limit_per_minute, rate_limit_per_day FROM api_keys WHERE key_hash = $1',
        [keyHash]
      );

      if (result.rows.length === 0) {
        return res.status(401).json({
          success: false,
          error: 'INVALID_API_KEY',
          message: 'API key not found. Generate one at https://dev.plainplan.click',
        });
      }

      const apiKey = result.rows[0];

      if (!apiKey.is_active) {
        return res.status(401).json({
          success: false,
          error: 'KEY_DISABLED',
          message: 'This API key has been deactivated',
        });
      }

      // Update last_used_at (fire and forget — don't block the request)
      pool.query('UPDATE api_keys SET last_used_at = NOW() WHERE id = $1', [apiKey.id]).catch(() => {});

      req.apiKey = apiKey;
      next();
    } catch (err) {
      console.error('Auth middleware error:', err.message);
      return res.status(500).json({
        success: false,
        error: 'AUTH_ERROR',
        message: 'Authentication service error',
      });
    }
  };
}

module.exports = { authenticateApiKey, generateApiKey, hashKey };
