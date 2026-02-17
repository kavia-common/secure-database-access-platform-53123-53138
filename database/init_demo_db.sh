#!/bin/bash
set -euo pipefail

# Repeatable PostgreSQL demo initialization:
# - creates least-privilege roles: mcp_ro (read-only) and mcp_rw (read-write)
# - creates demo schema + tables + seed data
# - grants privileges appropriately
#
# Uses the local superuser 'postgres' via sudo, matching the existing container pattern.

DB_NAME="${DB_NAME:-myapp}"
DB_PORT="${DB_PORT:-5000}"

# Least-privilege roles for MCP usage
MCP_RO_USER="${MCP_RO_USER:-mcp_ro}"
MCP_RO_PASSWORD="${MCP_RO_PASSWORD:-mcp_ro_password_change_me}"
MCP_RW_USER="${MCP_RW_USER:-mcp_rw}"
MCP_RW_PASSWORD="${MCP_RW_PASSWORD:-mcp_rw_password_change_me}"

# Demo schema name (kept stable so MCP prompts/docs can rely on it)
DEMO_SCHEMA="${DEMO_SCHEMA:-demo}"

PG_VERSION="$(ls /usr/lib/postgresql/ | head -1)"
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

echo "Initializing repeatable demo content..."
echo "- PG version: ${PG_VERSION}"
echo "- DB: ${DB_NAME}"
echo "- Port: ${DB_PORT}"
echo "- Read-only role: ${MCP_RO_USER}"
echo "- Read-write role: ${MCP_RW_USER}"
echo "- Schema: ${DEMO_SCHEMA}"
echo ""

# Ensure DB exists (idempotent)
sudo -u postgres "${PG_BIN}/createdb" -p "${DB_PORT}" "${DB_NAME}" 2>/dev/null || true

# 1) Create/ensure roles (idempotent)
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d postgres -v ON_ERROR_STOP=1 -c "DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${MCP_RO_USER}') THEN
    CREATE ROLE ${MCP_RO_USER} WITH LOGIN PASSWORD '${MCP_RO_PASSWORD}';
  END IF;
  ALTER ROLE ${MCP_RO_USER} WITH PASSWORD '${MCP_RO_PASSWORD}';
END
\$\$;"

sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d postgres -v ON_ERROR_STOP=1 -c "DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${MCP_RW_USER}') THEN
    CREATE ROLE ${MCP_RW_USER} WITH LOGIN PASSWORD '${MCP_RW_PASSWORD}';
  END IF;
  ALTER ROLE ${MCP_RW_USER} WITH PASSWORD '${MCP_RW_PASSWORD}';
END
\$\$;"

# 2) Create schema and tables (idempotent)
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "CREATE SCHEMA IF NOT EXISTS ${DEMO_SCHEMA};"

sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "CREATE TABLE IF NOT EXISTS ${DEMO_SCHEMA}.customers (
  id BIGSERIAL PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  full_name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);"

sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "CREATE TABLE IF NOT EXISTS ${DEMO_SCHEMA}.orders (
  id BIGSERIAL PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES ${DEMO_SCHEMA}.customers(id),
  order_total_cents INTEGER NOT NULL CHECK (order_total_cents >= 0),
  status TEXT NOT NULL CHECK (status IN ('pending','paid','shipped','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);"

# 3) Seed data (repeatable): insert only if unique email not present
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "INSERT INTO ${DEMO_SCHEMA}.customers (email, full_name)
VALUES ('ada@example.com','Ada Lovelace')
ON CONFLICT (email) DO NOTHING;"

sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "INSERT INTO ${DEMO_SCHEMA}.customers (email, full_name)
VALUES ('grace@example.com','Grace Hopper')
ON CONFLICT (email) DO NOTHING;"

sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "INSERT INTO ${DEMO_SCHEMA}.customers (email, full_name)
VALUES ('linus@example.com','Linus Torvalds')
ON CONFLICT (email) DO NOTHING;"

# For orders, insert based on email lookups; avoid duplication with a simple uniqueness heuristic:
# "same customer_id, same total, same status" is treated as duplicate for demo purposes.
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "INSERT INTO ${DEMO_SCHEMA}.orders (customer_id, order_total_cents, status)
SELECT c.id, 2599, 'paid'
FROM ${DEMO_SCHEMA}.customers c
WHERE c.email = 'ada@example.com'
AND NOT EXISTS (
  SELECT 1 FROM ${DEMO_SCHEMA}.orders o
  WHERE o.customer_id = c.id AND o.order_total_cents = 2599 AND o.status = 'paid'
);"

sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "INSERT INTO ${DEMO_SCHEMA}.orders (customer_id, order_total_cents, status)
SELECT c.id, 1099, 'shipped'
FROM ${DEMO_SCHEMA}.customers c
WHERE c.email = 'grace@example.com'
AND NOT EXISTS (
  SELECT 1 FROM ${DEMO_SCHEMA}.orders o
  WHERE o.customer_id = c.id AND o.order_total_cents = 1099 AND o.status = 'shipped'
);"

sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "INSERT INTO ${DEMO_SCHEMA}.orders (customer_id, order_total_cents, status)
SELECT c.id, 4999, 'pending'
FROM ${DEMO_SCHEMA}.customers c
WHERE c.email = 'linus@example.com'
AND NOT EXISTS (
  SELECT 1 FROM ${DEMO_SCHEMA}.orders o
  WHERE o.customer_id = c.id AND o.order_total_cents = 4999 AND o.status = 'pending'
);"

# 4) Grant privileges (least privilege)
# Database connect
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d postgres -v ON_ERROR_STOP=1 -c "GRANT CONNECT ON DATABASE ${DB_NAME} TO ${MCP_RO_USER};"
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d postgres -v ON_ERROR_STOP=1 -c "GRANT CONNECT ON DATABASE ${DB_NAME} TO ${MCP_RW_USER};"

# Schema usage
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "GRANT USAGE ON SCHEMA ${DEMO_SCHEMA} TO ${MCP_RO_USER};"
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "GRANT USAGE ON SCHEMA ${DEMO_SCHEMA} TO ${MCP_RW_USER};"

# Table privileges
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "GRANT SELECT ON ALL TABLES IN SCHEMA ${DEMO_SCHEMA} TO ${MCP_RO_USER};"
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ${DEMO_SCHEMA} TO ${MCP_RW_USER};"

# Sequence privileges (for inserts into bigserial)
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA ${DEMO_SCHEMA} TO ${MCP_RW_USER};"

# Default privileges for future objects in schema
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "ALTER DEFAULT PRIVILEGES IN SCHEMA ${DEMO_SCHEMA} GRANT SELECT ON TABLES TO ${MCP_RO_USER};"
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "ALTER DEFAULT PRIVILEGES IN SCHEMA ${DEMO_SCHEMA} GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${MCP_RW_USER};"
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "ALTER DEFAULT PRIVILEGES IN SCHEMA ${DEMO_SCHEMA} GRANT USAGE, SELECT ON SEQUENCES TO ${MCP_RW_USER};"

echo ""
echo "✓ Demo DB initialization complete."
echo ""
echo "Connection strings (for MCP server):"
echo "  Read-only : postgresql://${MCP_RO_USER}:<password>@localhost:${DB_PORT}/${DB_NAME}"
echo "  Read-write: postgresql://${MCP_RW_USER}:<password>@localhost:${DB_PORT}/${DB_NAME}"
echo ""
echo "Demo schema objects:"
echo "  - ${DEMO_SCHEMA}.customers"
echo "  - ${DEMO_SCHEMA}.orders"
