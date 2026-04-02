-- ============================================================
-- PlanPlain — Full PostgreSQL Schema Dump
-- Structure only (no data)
-- Generated: 2026-04-02
-- ============================================================


-- ============================================================
-- MIGRATION TRACKING TABLE
-- Created by migrate.js on every deploy (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS _migrations (
  id        SERIAL PRIMARY KEY,
  name      VARCHAR(255) NOT NULL UNIQUE,
  applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- ============================================================
-- USERS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS users (
  id                       SERIAL PRIMARY KEY,
  email                    VARCHAR(255) NOT NULL,
  name                     VARCHAR(255),
  password_hash            VARCHAR(255),
  created_at               TIMESTAMPTZ DEFAULT NOW(),
  updated_at               TIMESTAMPTZ DEFAULT NOW(),
  stripe_subscription_id   VARCHAR(255),
  subscription_status      VARCHAR(50),
  subscription_plan        VARCHAR(255),
  subscription_expires_at  TIMESTAMPTZ,
  subscription_updated_at  TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique_idx
  ON users (LOWER(email));

CREATE INDEX IF NOT EXISTS users_stripe_subscription_id_idx
  ON users (stripe_subscription_id);


-- ============================================================
-- API_KEYS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS api_keys (
  id                    SERIAL PRIMARY KEY,
  key_hash              VARCHAR(64)  NOT NULL UNIQUE,
  key_prefix            VARCHAR(12)  NOT NULL,
  user_id               INTEGER REFERENCES users(id) ON DELETE CASCADE,
  email                 VARCHAR(255) NOT NULL,
  name                  VARCHAR(255) DEFAULT 'default',
  created_at            TIMESTAMPTZ  DEFAULT NOW(),
  last_used_at          TIMESTAMPTZ,
  is_active             BOOLEAN      DEFAULT true,
  rate_limit_per_minute INTEGER      DEFAULT 10,
  rate_limit_per_day    INTEGER      DEFAULT 200
);

CREATE INDEX IF NOT EXISTS idx_api_keys_key_hash
  ON api_keys (key_hash);

CREATE INDEX IF NOT EXISTS idx_api_keys_email
  ON api_keys (LOWER(email));


-- ============================================================
-- ANALYSIS_LOGS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS analysis_logs (
  id                   SERIAL PRIMARY KEY,
  api_key_id           INTEGER REFERENCES api_keys(id) ON DELETE SET NULL,
  plan_hash            VARCHAR(64),
  resources_total      INTEGER DEFAULT 0,
  resources_created    INTEGER DEFAULT 0,
  resources_updated    INTEGER DEFAULT 0,
  resources_destroyed  INTEGER DEFAULT 0,
  resources_replaced   INTEGER DEFAULT 0,
  max_risk_level       VARCHAR(10),
  processing_time_ms   INTEGER,
  ai_tokens_used       INTEGER DEFAULT 0,
  created_at           TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_analysis_logs_api_key
  ON analysis_logs (api_key_id, created_at DESC);


-- ============================================================
-- API_REQUESTS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS api_requests (
  id                  SERIAL PRIMARY KEY,
  api_key_hash        VARCHAR(64),
  request_size_bytes  INTEGER,
  response_time_ms    INTEGER,
  risk_level          VARCHAR(20),
  resource_count      INTEGER,
  error               TEXT,
  created_at          TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_api_requests_created_at
  ON api_requests (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_api_requests_api_key_hash
  ON api_requests (api_key_hash);
