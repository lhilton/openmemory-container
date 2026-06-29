# openmemory-container

Pre-built, automatically updated **amd64** Docker images for
[OpenMemory](https://github.com/CaviraOSS/OpenMemory)'s **backend** API and **dashboard** web UI,
published to GitHub Container Registry with cosign signatures and SLSA provenance.

OpenMemory ships Dockerfiles but does not publish container images. This repo tracks OpenMemory's
release tags, builds the upstream Dockerfiles verbatim (no fork, no source changes), and publishes
ready-to-pull images for `linux/amd64`:

| Image | Purpose |
|---|---|
| `ghcr.io/lhilton/openmemory` | Backend API + MCP server (`:8080`) |
| `ghcr.io/lhilton/openmemory-dashboard` | Next.js web UI (`:3000`) |

> **Architecture:** images are built **amd64-only** (e.g. AMD Ryzen / Intel hosts). There is no arm64
> build. The backend's `sqlite3` native module and Postgres `pgvector` paths are exercised on amd64.

## Quickstart (Postgres — recommended)

```bash
git clone https://github.com/lhilton/openmemory-container.git
cd openmemory-container
cp .env.example .env          # then edit OM_PG_PASSWORD
docker compose -f docker-compose.sample.yaml up -d
```

Once healthy:

| Service | URL |
|---|---|
| Backend API | http://localhost:8080 (health: `/health`) |
| Dashboard | http://localhost:3000 |

The OpenMemory backend **self-initializes** Postgres on first boot: it connects, creates the database
if missing, runs `CREATE EXTENSION IF NOT EXISTS vector`, creates all tables, and builds an HNSW index
for fast vector search. There are **no init scripts and no migration step**. Because of the `vector`
extension, the sample uses the `pgvector/pgvector:pg17` image — a plain `postgres` image will not work.

Vectors and metadata both live in the same Postgres database (`OM_METADATA_BACKEND=postgres`).

### Dashboard ↔ backend wiring

The dashboard serves the browser a same-origin proxy at `/api/openmemory/*`. The image is built with
empty `NEXT_PUBLIC_*` so nothing is baked in — you point it at the backend **at runtime** with
`OPENMEMORY_API_URL`. In the sample that's `http://openmemory:8080` over the compose network. If you set
`OM_API_KEY` on the backend, set the same value as `OPENMEMORY_API_KEY` (or `OM_API_KEY`) on the dashboard
so the proxy authenticates.

## SQLite mode (zero dependencies)

If you don't want Postgres, run only the backend (and optionally the dashboard) and let it use its
default embedded SQLite store at `/data`:

```yaml
services:
  openmemory:
    image: ghcr.io/lhilton/openmemory:latest
    ports:
      - "8080:8080"
    volumes:
      - openmemory_data:/data
    restart: unless-stopped
volumes:
  openmemory_data:
```

Leave `OM_METADATA_BACKEND` unset (defaults to `sqlite`). Embeddings default to `synthetic`, so it runs
fully offline with no API keys.

## Configuration

Copy `.env.example` to `.env`. Common values:

| Variable | Default | Description |
|---|---|---|
| `OM_PG_PASSWORD` | — | Postgres password (sample refuses to start without it) |
| `OM_PG_USER` | `openmemory` | Postgres user |
| `OM_PG_DB` | `openmemory` | Postgres database |
| `OM_PORT` | `8080` | Backend host port |
| `OM_DASHBOARD_PORT` | `3000` | Dashboard host port |
| `OM_API_KEY` | empty | Optional API key; empty disables auth |
| `OM_EMBEDDINGS` | `synthetic` | Set `openai` (+ `OPENAI_API_KEY`) for real embeddings |

The backend accepts many more `OM_*` knobs (rate limiting, decay, reflection, compression, etc.) — see
upstream [`docker-compose.yml`](https://github.com/CaviraOSS/OpenMemory/blob/main/docker-compose.yml)
for the full list. They pass straight through as container env vars.

## Pulling images

```bash
docker pull ghcr.io/lhilton/openmemory:latest
docker pull ghcr.io/lhilton/openmemory-dashboard:latest
```

GitHub packages are **private** on first publish. To allow anonymous pulls, make both packages public:
your GitHub profile → **Packages** → `openmemory` / `openmemory-dashboard` → **Package settings** →
**Change visibility** → Public. Otherwise authenticate first:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
```

## Available image tags

Each tracking build publishes immutable tags first, then promotes mutable channel tags to the same
digest after signing + attestation verification.

Example for upstream release `v1.2.3`:

| Tag | Meaning |
|---|---|
| `:1.2.3` | Exact upstream release (normalized, no `v`) |
| `:v1.2.3` | Exact upstream release (`v`-prefixed alias) |
| `:openmemory-<sha>` | Exact upstream commit SHA |
| `:latest` | Mutable latest verified tracking build |
| `:1.2` | Mutable major.minor channel |
| `:1` | Mutable major channel |

Manual historical rebuilds (`tag: vX.Y.Z` dispatch) publish only the exact tags and never move
`:latest`, `:X.Y`, `:X`, nor update `.upstream-release`.

## Verifying images

```bash
cosign verify \
  --certificate-identity 'https://github.com/lhilton/openmemory-container/.github/workflows/openmemory-upstream-rebuild.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/lhilton/openmemory:latest

gh attestation verify oci://ghcr.io/lhilton/openmemory:latest \
  --repo lhilton/openmemory-container
```

Replace `openmemory` with `openmemory-dashboard` to verify the dashboard image.

## How images are published

The workflow (`.github/workflows/openmemory-upstream-rebuild.yml`) runs daily at 09:17 UTC and can be
run manually from GitHub Actions. It:

1. Resolves the latest non-prerelease OpenMemory release tag (accepts both `vX.Y.Z` and `X.Y.Z` forms),
   or validates a manual `tag`.
2. Resolves the tag to a commit SHA (TOCTOU-defended) and checks whether a build is needed.
3. Builds `openmemory` (from `packages/openmemory-js`) and `openmemory-dashboard` (from `dashboard`) at
   that SHA, for `linux/amd64`.
4. Pushes immutable tags, signs the digest (cosign keyless), attests SLSA provenance, and verifies both.
5. Promotes mutable tags only for normal tracking builds.
6. Updates `.upstream-release` only for normal tracking builds.

Manual dispatch options:

- `force: true` — rebuild the current latest release and re-promote mutable tags.
- `tag: vX.Y.Z` — rebuild a specific historical release; never promotes mutable tags.

The workflow only publishes from `refs/heads/main`, matching the strict OIDC identity used for
verification.

```bash
# Trigger a build without waiting for the daily cron:
gh workflow run openmemory-upstream-rebuild.yml --repo lhilton/openmemory-container
gh run watch --repo lhilton/openmemory-container
```

## Attribution

OpenMemory source: https://github.com/CaviraOSS/OpenMemory (Apache-2.0).

This repo packages OpenMemory's Dockerfiles for automated GHCR publishing. It does not own or modify the
OpenMemory source.
