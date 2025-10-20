-- BotHive Plus Database Initialization
-- This script sets up the initial database configuration for each instance

-- Ensure UTF-8 encoding
SET client_encoding = 'UTF8';

-- Create extensions if they don't exist
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Set timezone
SET timezone = 'UTC';

-- Optimize PostgreSQL settings for BotHive Plus
ALTER SYSTEM SET max_connections = 200;  -- Adjusted for 2GB RAM
ALTER SYSTEM SET shared_buffers = '512MB';  -- Increased for better cache usage
ALTER SYSTEM SET effective_cache_size = '1GB';  -- Proportional to available memory
ALTER SYSTEM SET maintenance_work_mem = '128MB';  -- Increased for maintenance tasks
ALTER SYSTEM SET checkpoint_completion_target = 0.9;  -- Optimal setting for I/O balancing
ALTER SYSTEM SET wal_buffers = '16MB';  -- No change unless needed
ALTER SYSTEM SET default_statistics_target = 200;  -- Keep default unless performance issues arise

-- Log initialization
SELECT 'BotHive Plus database initialized successfully' as status;
