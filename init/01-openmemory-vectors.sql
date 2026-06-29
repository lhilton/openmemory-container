-- OpenMemory Postgres bootstrap (workaround for an upstream bug).
--
-- At the pinned commit, OpenMemory creates its vector column as an unbounded
-- `vector` and then builds an HNSW index on it. pgvector requires a FIXED
-- dimension for HNSW, so OpenMemory's own init aborts with
--   "column does not have dimensions"  (hnswbuild.c)
-- and Postgres mode fails half-initialized.
--
-- Pre-creating the table here with a dimensioned column makes OpenMemory's
-- idempotent `create table if not exists` a no-op and its `create index if not
-- exists ... using hnsw` succeed, so init completes and native pgvector ANN
-- search works. Runs once, on a fresh Postgres data volume.
--
-- IMPORTANT: the dimension below MUST match your embedding size. 1536 is correct
-- for OpenMemory's default `synthetic` embeddings and for OpenAI text-embedding-3
-- / ada-002. If you switch to an embedding model with a different dimension,
-- change 1536 here and reset the postgres volume (`docker compose down -v`).
--
-- Assumes the defaults OM_PG_SCHEMA=public and OM_VECTOR_TABLE=openmemory_vectors.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS public.openmemory_vectors (
    id         uuid,
    sector     text,
    user_id    text,
    project_id text,
    v          vector(1536),
    dim        integer NOT NULL,
    PRIMARY KEY (id, sector)
);
