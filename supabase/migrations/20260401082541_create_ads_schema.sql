-- Create the ads schema (separate from public)
CREATE SCHEMA IF NOT EXISTS ads;

-- Grant usage to supabase roles so RPC and PostgREST can access it
GRANT USAGE ON SCHEMA ads TO postgres, anon, authenticated, service_role;

-- Set default privileges so future tables are accessible
ALTER DEFAULT PRIVILEGES IN SCHEMA ads
  GRANT ALL ON TABLES TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA ads
  GRANT SELECT ON TABLES TO anon, authenticated;

-- Grant execute on functions so RPC calls work via PostgREST
ALTER DEFAULT PRIVILEGES IN SCHEMA ads
  GRANT EXECUTE ON FUNCTIONS TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA ads
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;
