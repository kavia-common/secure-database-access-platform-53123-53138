# PostgreSQL Repeatable Demo Setup (Step 02.00)

This container boots PostgreSQL and then initializes a repeatable demo schema + least-privilege roles for an MCP server.

## What gets created

### Roles (least privilege)

- **Read-only**: `mcp_ro`
  - Can `CONNECT` to the demo database
  - Can `USAGE` schema `demo`
  - Can `SELECT` from all tables in schema `demo`

- **Read-write**: `mcp_rw`
  - Can `CONNECT` to the demo database
  - Can `USAGE` schema `demo`
  - Can `SELECT, INSERT, UPDATE, DELETE` on all tables in schema `demo`
  - Can use sequences in schema `demo` (needed for `BIGSERIAL` inserts)

Passwords are intentionally simple defaults for a local demo and can be overridden via environment variables (see below).

### Demo schema/data

Schema: `demo`

Tables:
- `demo.customers`
- `demo.orders`

Seed rows are inserted idempotently (safe to run multiple times).

## How to start

Use the existing startup script:

```bash
./startup.sh
```

After startup, the container writes:

- `db_connection.txt` (existing): admin/app user connection string
- `mcp_connection_guidance.txt` (new): stable guidance for RO/RW URLs and demo schema
- `db_visualizer/postgres.env` (updated): includes MCP role env vars + suggested MCP URLs

## How to re-run demo seeding/role creation

```bash
./init_demo_db.sh
```

This is safe to run repeatedly.

## Environment variables (optional overrides)

These are optional. If not set, defaults are used.

- `DB_NAME` (default: `myapp`)
- `DB_PORT` (default: `5000`)
- `MCP_RO_USER` (default: `mcp_ro`)
- `MCP_RO_PASSWORD` (default: `mcp_ro_password_change_me`)
- `MCP_RW_USER` (default: `mcp_rw`)
- `MCP_RW_PASSWORD` (default: `mcp_rw_password_change_me`)
- `DEMO_SCHEMA` (default: `demo`)

## MCP server connection guidance

Use the contents of `mcp_connection_guidance.txt` as the authoritative “stable connection guidance” for the MCP server.

In general:
- Use the **RO** URL for *query-only* tools.
- Use the **RW** URL for *execute/write* tools.
- Prefer explicit schema-qualified queries (e.g., `SELECT * FROM demo.customers`).
