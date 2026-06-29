# openmemory-container

Pre-built, automatically updated **amd64** Docker images for
[OpenMemory](https://github.com/CaviraOSS/OpenMemory)'s **backend** API and **dashboard** web UI,
published to GitHub Container Registry with cosign signatures and SLSA provenance.

OpenMemory ships Dockerfiles but does not publish container images. This repo builds the upstream
Dockerfiles verbatim (no fork, no source changes) at a **pinned, tested commit** and publishes
ready-to-pull images for `linux/amd64`:

| Image | Purpose |
|---|---|
| `ghcr.io/lhilton/openmemory` | Backend API + MCP server (`:8080`) |
| `ghcr.io/lhilton/openmemory-dashboard` | Next.js web UI (`:3000`) |

> **Why a pinned commit instead of a release tag?** Upstream's current tagged releases can't build
> both images — `v1.2.3` has no dashboard Dockerfile and the `v1.3.0` prerelease ships no dashboard
> source. Only the `main` branch builds the backend **and** dashboard together, so this repo pins a
> known-good `main` commit (in [`.upstream-commit`](.upstream-commit)) and bumps it deliberately.

> **Architecture:** images are built **amd64-only** (e.g. AMD Ryzen / Intel hosts). There is no arm64
> build. The backend's `sqlite3` native module and Postgres `pgvector` paths are exercised on amd64.

## Quickstart (Postgres — recommended)

```bash
git clone https://github.com/lhilton/openmemory-container.git
cd openmemory-container
cp .env.example .env          # set OM_PG_PASSWORD and OM_API_KEY (openssl rand -hex 32)
docker compose -f docker-compose.sample.yaml up -d
```

Once healthy:

| Service | URL |
|---|---|
| Backend API | http://localhost:8080 (health: `/health`, public) |
| Dashboard | http://localhost:3000 |

Vectors and metadata both live in the same Postgres database (`OM_METADATA_BACKEND=postgres`), using the
`pgvector/pgvector:pg17` image (a plain `postgres` image will not work — `pgvector` is required).

> **Postgres needs a one-time init script (upstream bug).** OpenMemory creates its vector column as an
> unbounded `vector` and then tries to build an HNSW index on it — which pgvector rejects (`column does
> not have dimensions`), aborting its own init. The bundled `init/01-openmemory-vectors.sql` pre-creates
> the vector table at a **fixed dimension (1536)** on a fresh Postgres volume, so OpenMemory's idempotent
> schema/index creation then succeeds and native pgvector ANN search works. **1536 matches the default
> `synthetic` embeddings and OpenAI `text-embedding-3` / `ada-002`.** If you use a different embedding
> dimension, edit that file and reset the volume (`docker compose down -v`).

### API authentication

Protected endpoints (everything except `/health`) require an API key — without `OM_API_KEY` set, the
server returns **503** (`auth_not_configured`). Send the key as the `x-api-key` header:

```bash
curl -H "x-api-key: $OM_API_KEY" -H 'content-type: application/json' \
  -d '{"content":"remember this"}' http://localhost:8080/memory/add
curl -H "x-api-key: $OM_API_KEY" -H 'content-type: application/json' \
  -d '{"query":"what should I remember"}' http://localhost:8080/memory/query
```

For a no-auth deployment on a trusted LAN, drop `OM_API_KEY` and set `OM_DEV_ALLOW_NO_AUTH=true` instead.

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
    environment:
      OM_API_KEY: ${OM_API_KEY:?set OM_API_KEY}   # still required (or OM_DEV_ALLOW_NO_AUTH=true)
    volumes:
      - openmemory_data:/data
    restart: unless-stopped
volumes:
  openmemory_data:
```

Leave `OM_METADATA_BACKEND` unset (defaults to `sqlite`) — no Postgres, no init script. Embeddings
default to `synthetic`, so it needs no embedding-provider keys, but the API still requires `OM_API_KEY`
(see [API authentication](#api-authentication)).

## Using an existing Postgres + reverse proxy (Unraid / Compose Manager Plus)

If you already run Postgres and Caddy (or another reverse proxy), the self-contained sample above isn't
the right fit. See [`examples/`](examples/) for a guide and a compose file that points at an existing
`postgres18` on a shared network and sits behind an existing Caddy with public TLS.

## Configuration

Copy `.env.example` to `.env`. Common values:

| Variable | Default | Description |
|---|---|---|
| `OM_PG_PASSWORD` | — | Postgres password (sample refuses to start without it) |
| `OM_PG_USER` | `openmemory` | Postgres user |
| `OM_PG_DB` | `openmemory` | Postgres database |
| `OM_PORT` | `8080` | Backend host port |
| `OM_DASHBOARD_PORT` | `3000` | Dashboard host port |
| `OM_API_KEY` | — | **Required.** API key sent as `x-api-key`; unset → 503 on protected endpoints |
| `OM_EMBEDDINGS` | `synthetic` | Set `openai` (+ `OPENAI_API_KEY`) for real embeddings (keep dim 1536) |

The backend accepts many more `OM_*` knobs (rate limiting, decay, reflection, compression, etc.) — see
upstream [`docker-compose.yml`](https://github.com/CaviraOSS/OpenMemory/blob/main/docker-compose.yml)
for the full list. They pass straight through as container env vars.

## Pulling images

```bash
docker pull ghcr.io/lhilton/openmemory:latest
docker pull ghcr.io/lhilton/openmemory-dashboard:latest
```

These packages are **public** (published from a public repo, so GHCR linked them to its visibility) —
anonymous `docker pull` works with no login. To change visibility later: your GitHub profile →
**Packages** → `openmemory` / `openmemory-dashboard` → **Package settings** → **Change visibility**.

If a package is ever made private, authenticate before pulling:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
```

## Available image tags

Each build publishes immutable commit-SHA tags first, then promotes `:latest` to the same digest after
signing + attestation verification.

| Tag | Meaning |
|---|---|
| `:openmemory-<full-sha>` | Exact upstream commit (immutable) |
| `:<short-sha>` | Exact upstream commit, 7-char short form (immutable) |
| `:latest` | The currently pinned, verified build (mutable) |

Ad-hoc builds via `workflow_dispatch` with a `ref` input publish only the two immutable SHA tags and
never move `:latest`.

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

The workflow (`.github/workflows/openmemory-upstream-rebuild.yml`) builds the commit pinned in
[`.upstream-commit`](.upstream-commit). It:

1. Resolves the pinned ref (or a `workflow_dispatch` `ref` input) to a full commit SHA.
2. Builds `openmemory` (from `packages/openmemory-js`) and `openmemory-dashboard` (from `dashboard`) at
   that SHA, for `linux/amd64`.
3. Pushes immutable SHA tags, signs the digest (cosign keyless), attests SLSA provenance, verifies both.
4. Promotes `:latest` to the verified digest — only for pinned builds (not ad-hoc `ref` dispatches).

**To update the pinned version**, edit `.upstream-commit` to a new commit SHA and push to `main`:

```bash
echo <new-commit-sha> > .upstream-commit
git commit -am "bump: OpenMemory <new-commit-sha>" && git push
```

The push triggers a build and moves `:latest`. To test an arbitrary commit/branch/tag without moving
`:latest`, run it manually:

```bash
gh workflow run openmemory-upstream-rebuild.yml --repo lhilton/openmemory-container -f ref=<sha-or-branch>
gh run watch --repo lhilton/openmemory-container
```

The workflow only publishes from `refs/heads/main`, matching the strict OIDC identity used for
verification.

## Attribution

OpenMemory source: https://github.com/CaviraOSS/OpenMemory (Apache-2.0).

This repo packages OpenMemory's Dockerfiles for automated GHCR publishing. It does not own or modify the
OpenMemory source.
