#!/bin/bash

# Minimal PostgreSQL startup script with full paths
DB_NAME="myapp"
DB_USER="appuser"
DB_PASSWORD="dbuser123"
DB_PORT="5000"

echo "Starting PostgreSQL setup..."

# Find PostgreSQL version and set paths
PG_VERSION=$(ls /usr/lib/postgresql/ | head -1)
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

echo "Found PostgreSQL version: ${PG_VERSION}"

# Check if PostgreSQL is already running on the specified port
if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
    echo "PostgreSQL is already running on port ${DB_PORT}!"
    echo "Database: ${DB_NAME}"
    echo "User: ${DB_USER}"
    echo "Port: ${DB_PORT}"
    echo ""
    echo "To connect to the database, use:"
    echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
    
    # Check if connection info file exists
    if [ -f "db_connection.txt" ]; then
        echo "Or use: $(cat db_connection.txt)"
    fi
    
    echo ""
    echo "Script stopped - server already running."
    exit 0
fi

# Also check if there's a PostgreSQL process running (in case pg_isready fails)
if pgrep -f "postgres.*-p ${DB_PORT}" > /dev/null 2>&1; then
    echo "Found existing PostgreSQL process on port ${DB_PORT}"
    echo "Attempting to verify connection..."
    
    # Try to connect and verify the database exists
    if sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c '\q' 2>/dev/null; then
        echo "Database ${DB_NAME} is accessible."
        echo "Script stopped - server already running."
        exit 0
    fi
fi

# Initialize PostgreSQL data directory if it doesn't exist
if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
    echo "Initializing PostgreSQL..."
    sudo -u postgres ${PG_BIN}/initdb -D /var/lib/postgresql/data
fi

# Start PostgreSQL server in background
echo "Starting PostgreSQL server..."
sudo -u postgres ${PG_BIN}/postgres -D /var/lib/postgresql/data -p ${DB_PORT} &

# Wait for PostgreSQL to start
echo "Waiting for PostgreSQL to start..."
sleep 5

# Check if PostgreSQL is running
for i in {1..15}; do
    if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
        echo "PostgreSQL is ready!"
        break
    fi
    echo "Waiting... ($i/15)"
    sleep 2
done

# Create database and user
echo "Setting up database and user..."
sudo -u postgres ${PG_BIN}/createdb -p ${DB_PORT} ${DB_NAME} 2>/dev/null || echo "Database might already exist"

# Set up user and permissions with proper schema ownership
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d postgres << EOF
-- Create user if doesn't exist
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
END
\$\$;

-- Grant database-level permissions
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};

-- Connect to the specific database for schema-level permissions
\c ${DB_NAME}

-- For PostgreSQL 15+, we need to handle public schema permissions differently
-- First, grant usage on public schema
GRANT USAGE ON SCHEMA public TO ${DB_USER};

-- Grant CREATE permission on public schema
GRANT CREATE ON SCHEMA public TO ${DB_USER};

-- Make the user owner of all future objects they create in public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};

-- If you want the user to be able to create objects without restrictions,
-- you can make them the owner of the public schema (optional but effective)
-- ALTER SCHEMA public OWNER TO ${DB_USER};

-- Alternative: Grant all privileges on schema public to the user
GRANT ALL ON SCHEMA public TO ${DB_USER};

-- Ensure the user can work with any existing objects
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${DB_USER};
EOF

# Additionally, connect to the specific database to ensure permissions
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} << EOF
-- Double-check permissions are set correctly in the target database
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};

-- Show current permissions for debugging
\dn+ public
EOF

# Save connection command to a file
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}" > db_connection.txt
echo "Connection string saved to db_connection.txt"

# ---------------------------------------------------------------------------
# Repeatable demo setup (least-privilege MCP roles + schema + seed data)
# ---------------------------------------------------------------------------
# Stable demo roles (used by the MCP server)
export MCP_RO_USER="${MCP_RO_USER:-mcp_ro}"
export MCP_RO_PASSWORD="${MCP_RO_PASSWORD:-mcp_ro_password_change_me}"
export MCP_RW_USER="${MCP_RW_USER:-mcp_rw}"
export MCP_RW_PASSWORD="${MCP_RW_PASSWORD:-mcp_rw_password_change_me}"
export DEMO_SCHEMA="${DEMO_SCHEMA:-demo}"

if [ -f "./init_demo_db.sh" ]; then
    echo ""
    echo "Initializing demo schema/data + MCP roles..."
    chmod +x ./init_demo_db.sh || true
    DB_NAME="${DB_NAME}" DB_PORT="${DB_PORT}" \
      MCP_RO_USER="${MCP_RO_USER}" MCP_RO_PASSWORD="${MCP_RO_PASSWORD}" \
      MCP_RW_USER="${MCP_RW_USER}" MCP_RW_PASSWORD="${MCP_RW_PASSWORD}" \
      DEMO_SCHEMA="${DEMO_SCHEMA}" \
      ./init_demo_db.sh || echo "⚠ Demo init failed (see logs above)."
fi

# Save environment variables to a file (for db_visualizer and local tooling)
cat > db_visualizer/postgres.env << EOF
export POSTGRES_URL="postgresql://localhost:${DB_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${DB_PORT}"

# MCP least-privilege demo roles
export MCP_RO_USER="${MCP_RO_USER}"
export MCP_RO_PASSWORD="${MCP_RO_PASSWORD}"
export MCP_RW_USER="${MCP_RW_USER}"
export MCP_RW_PASSWORD="${MCP_RW_PASSWORD}"
export DEMO_SCHEMA="${DEMO_SCHEMA}"

# Suggested MCP server connection strings (use as DATABASE_URL depending on mode)
export MCP_POSTGRES_URL_RO="postgresql://${MCP_RO_USER}:${MCP_RO_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}"
export MCP_POSTGRES_URL_RW="postgresql://${MCP_RW_USER}:${MCP_RW_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}"
EOF

# Stable connection guidance for the MCP server to use
cat > mcp_connection_guidance.txt << EOF
Stable PostgreSQL connection guidance (repeatable demo)
====================================================

Base DB (admin/demo owner)
- Database: ${DB_NAME}
- Port:     ${DB_PORT}
- Owner:    ${DB_USER}

Least-privilege MCP roles (recommended)
- Read-only role:
    username: ${MCP_RO_USER}
    password: ${MCP_RO_PASSWORD}
    url: postgresql://${MCP_RO_USER}:<password>@localhost:${DB_PORT}/${DB_NAME}

- Read-write role:
    username: ${MCP_RW_USER}
    password: ${MCP_RW_PASSWORD}
    url: postgresql://${MCP_RW_USER}:<password>@localhost:${DB_PORT}/${DB_NAME}

Demo schema (seeded)
- ${DEMO_SCHEMA}.customers
- ${DEMO_SCHEMA}.orders

Notes for MCP server configuration
- Use the RO URL for query-only mode.
- Use the RW URL only for tools that perform INSERT/UPDATE/DELETE.
- Keep search_path explicit in queries (e.g., SELECT * FROM ${DEMO_SCHEMA}.customers).
EOF

echo "PostgreSQL setup complete!"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Port: ${DB_PORT}"
echo ""

echo "Environment variables saved to db_visualizer/postgres.env"
echo "Stable MCP connection guidance saved to mcp_connection_guidance.txt"
echo "To use with Node.js viewer, run: source db_visualizer/postgres.env"

echo ""
echo "To connect (admin/app user):"
echo "  psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
echo "  $(cat db_connection.txt)"

echo ""
echo "To connect (MCP read-only role):"
echo "  psql postgresql://${MCP_RO_USER}:${MCP_RO_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}"

echo "To connect (MCP read-write role):"
echo "  psql postgresql://${MCP_RW_USER}:${MCP_RW_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}"
