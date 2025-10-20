#!/bin/bash
# Convert Windows line endings to Unix
sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh
set -e

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until pg_isready -h "${PGHOST:-postgres}" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}"
do
  echo "PostgreSQL is unavailable - sleeping 2s"
  sleep 2
done

echo "PostgreSQL is up - executing database initialization"

# Check if this is the first run by looking for migration status
MIGRATION_STATUS_FILE="/app/data/.migration_status"
MIGRATIONS_DIR="/app/migrations"

# Function to check if migration has been applied
is_migration_applied() {
    local migration_file=$1
    if [ -f "$MIGRATION_STATUS_FILE" ]; then
        grep -q "^${migration_file}:applied:" "$MIGRATION_STATUS_FILE"
    else
        return 1  # Not applied if status file doesn't exist
    fi
}

# Function to mark migration as applied
mark_migration_applied() {
    local migration_file=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Create status file if it doesn't exist
    if [ ! -f "$MIGRATION_STATUS_FILE" ]; then
        mkdir -p "$(dirname "$MIGRATION_STATUS_FILE")"
        echo "# Migration Status - Auto-generated" > "$MIGRATION_STATUS_FILE"
    fi

    # Update or add the migration status
    if grep -q "^${migration_file}:" "$MIGRATION_STATUS_FILE"; then
        sed -i "s/^${migration_file}:.*/${migration_file}:applied:${timestamp}/" "$MIGRATION_STATUS_FILE"
    else
        echo "${migration_file}:applied:${timestamp}" >> "$MIGRATION_STATUS_FILE"
    fi

    echo "Marked migration as applied: $migration_file"
}

# Run migrations only if they haven't been applied
echo "Checking for pending migrations..."

if [ -d "$MIGRATIONS_DIR" ]; then
    for migration_file in "$MIGRATIONS_DIR"/*.sql; do
        if [ -f "$migration_file" ]; then
            migration_name=$(basename "$migration_file")

            if ! is_migration_applied "$migration_name"; then
                echo "Applying migration: $migration_name"
                echo "Using database: ${PGDATABASE:-powerchat}"
                if psql -h "${PGHOST:-postgres}" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}" -d "${PGDATABASE:-powerchat}" -f "$migration_file"; then
                    mark_migration_applied "$migration_name"
                    echo "Migration applied successfully: $migration_name"
                else
                    echo "Migration failed: $migration_name"
                    echo "Database connection details:"
                    echo "  Host: ${PGHOST:-postgres}"
                    echo "  Port: ${PGPORT:-5432}"
                    echo "  User: ${PGUSER:-postgres}"
                    echo "  Database: ${PGDATABASE:-powerchat}"
                    exit 1
                fi
            else
                echo "Migration already applied: $migration_name"
            fi
        fi
    done
    echo "All migrations processed!"
else
    echo "No migrations directory found, skipping migrations"
fi

# Start the application
echo "Starting the application..."
exec "$@"
