/**
 * Rate Limiting Middleware
 *
 * In-memory sliding window rate limiter, per API key.
 * Tracks per-minute and per-day limits.
 */

// In-memory store: apiKeyId → [timestamp, timestamp, ...]
const requestLog = new Map();

// Clean up old entries every 5 minutes
setInterval(() => {
  const cutoff = Date.now() - 86400000; // 24h ago
  for (const [key, timestamps] of requestLog.entries()) {
    const filtered = timestamps.filter(t => t > cutoff);
    if (filtered.length === 0) {
      requestLog.delete(key);
    } else {
      requestLog.set(key, filtered);
    }
  }
}, 300000);

/**
 * Express middleware for rate limiting
 * Requires req.apiKey to be set (run after auth middleware)
 */
function rateLimit() {
  return (req, res, next) => {
    const apiKey = req.apiKey;
    if (!apiKey) {
      return next(); // No API key = no rate limiting (shouldn't happen if auth middleware runs first)
    }

    const keyId = String(apiKey.id);
    const now = Date.now();
    const perMinute = apiKey.rate_limit_per_minute || 10;
    const perDay = apiKey.rate_limit_per_day || 200;

    // Get or create request log for this key
    if (!requestLog.has(keyId)) {
      requestLog.set(keyId, []);
    }

    const timestamps = requestLog.get(keyId);

    // Clean entries older than 24h
    const dayAgo = now - 86400000;
    const recentTimestamps = timestamps.filter(t => t > dayAgo);
    requestLog.set(keyId, recentTimestamps);

    // Check per-minute limit
    const minuteAgo = now - 60000;
    const lastMinute = recentTimestamps.filter(t => t > minuteAgo);
    if (lastMinute.length >= perMinute) {
      const oldestInWindow = Math.min(...lastMinute);
      const retryAfter = Math.ceil((oldestInWindow + 60000 - now) / 1000);

      res.set('Retry-After', String(Math.max(retryAfter, 1)));
      res.set('X-RateLimit-Limit', String(perMinute));
      res.set('X-RateLimit-Remaining', '0');
      res.set('X-RateLimit-Reset', String(Math.ceil((oldestInWindow + 60000) / 1000)));

      return res.status(429).json({
        success: false,
        error: 'RATE_LIMITED',
        message: `Rate limit exceeded (${perMinute}/minute). Try again in ${Math.max(retryAfter, 1)}s`,
        retry_after: Math.max(retryAfter, 1),
      });
    }

    // Check per-day limit
    if (recentTimestamps.length >= perDay) {
      const oldestInDay = Math.min(...recentTimestamps);
      const retryAfter = Math.ceil((oldestInDay + 86400000 - now) / 1000);

      res.set('Retry-After', String(Math.max(retryAfter, 1)));
      res.set('X-RateLimit-Limit', String(perDay));
      res.set('X-RateLimit-Remaining', '0');

      return res.status(429).json({
        success: false,
        error: 'RATE_LIMITED',
        message: `Daily rate limit exceeded (${perDay}/day). Upgrade your plan for higher limits.`,
        retry_after: Math.max(retryAfter, 1),
      });
    }

    // Record this request
    recentTimestamps.push(now);

    // Set rate limit headers
    const remaining = Math.min(perMinute - lastMinute.length - 1, perDay - recentTimestamps.length);
    res.set('X-RateLimit-Limit', String(perMinute));
    res.set('X-RateLimit-Remaining', String(Math.max(remaining, 0)));

    next();
  };
}

module.exports = { rateLimit };
