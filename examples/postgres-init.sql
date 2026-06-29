-- =============================================================================
-- One-time setup for OpenMemory on an EXISTING Postgres (e.g. `postgres18`,
-- running an image with pgvector such as pgvector/pgvector:pg18-trixie).
--
-- Run as a SUPERUSER (the `postgres` role). The CREATE EXTENSION line needs
-- superuser; everything the app does afterwards runs fine as the non-superuser
-- `openmemory` role created here (verified end-to-end).
--
--   docker exec -i postgres18 psql -v ON_ERROR_STOP=1 -U postgres < postgres-init.sql
--
-- This pre-creates the vector table at a FIXED dimension (1536) so OpenMemory's
-- HNSW index can build — a workaround for an upstream bug where it otherwise
-- creates an unbounded `vector` column and the HNSW index fails. 1536 matches the
-- default `synthetic` embeddings and OpenAI text-embedding-3 / ada-002. Use a
-- different number only if you change embedding models (then DROP the table first).
-- =============================================================================

CREATE DATABASE openmemory;

-- Set this password to the SAME value as OM_PG_PASSWORD in the compose stack .env:
CREATE USER openmemory WITH PASSWORD 'CHANGE_ME';
GRANT ALL PRIVILEGES ON DATABASE openmemory TO openmemory;

\connect openmemory

CREATE EXTENSION IF NOT EXISTS vector;        -- requires superuser
GRANT ALL ON SCHEMA public TO openmemory;     -- PG15+: app needs CREATE on schema
ALTER SCHEMA public OWNER TO openmemory;

CREATE TABLE IF NOT EXISTS public.openmemory_vectors (
    id         uuid,
    sector     text,
    user_id    text,
    project_id text,
    v          vector(1536),
    dim        integer NOT NULL,
    PRIMARY KEY (id, sector)
);
ALTER TABLE public.openmemory_vectors OWNER TO openmemory;
