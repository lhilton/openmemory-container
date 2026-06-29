-- =============================================================================
-- One-time setup for OpenMemory on an EXISTING Postgres (e.g. `postgres18`,
-- running an image with pgvector such as pgvector/pgvector:pg18-trixie).
--
-- EASIEST — run the whole file with psql, which understands the \connect:
--   docker exec -i postgres18 psql -v ON_ERROR_STOP=1 -U postgres < postgres-init.sql
--
-- GUI CLIENTS (DBeaver, pgAdmin, TablePlus, …) DO NOT understand the psql
-- meta-command `\connect`. Run the two PARTs below separately instead:
--   PART 1 — while connected to your maintenance DB ("postgres").
--   PART 2 — RECONNECT your client to the "openmemory" database, then run it.
-- The extension and table are per-database, so PART 2 MUST run while connected to
-- "openmemory" — otherwise you'll get "type vector does not exist" and then
-- "relation public.openmemory_vectors does not exist".
--
-- Pre-creating the vector table at a FIXED dimension (1536) works around an
-- upstream bug (OpenMemory otherwise makes an unbounded `vector` column and its
-- HNSW index fails). 1536 = default synthetic / OpenAI embeddings.
-- =============================================================================

-- ===== PART 1 — connected to the "postgres" (maintenance) database ===========
-- (CREATE DATABASE must run in autocommit, not inside a transaction block.)
CREATE DATABASE openmemory;
CREATE USER openmemory WITH PASSWORD 'CHANGE_ME';   -- must match OM_PG_PASSWORD
GRANT ALL PRIVILEGES ON DATABASE openmemory TO openmemory;

\connect openmemory
-- ^ psql switches database here. GUI users: ignore this line and manually
--   connect your client to the "openmemory" database before running PART 2.

-- ===== PART 2 — connected to the "openmemory" database =======================
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
