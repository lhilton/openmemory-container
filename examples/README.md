# Deploying on Unraid (Compose Manager Plus) with an existing Postgres + Caddy

The repo's top-level [`docker-compose.sample.yaml`](../docker-compose.sample.yaml) is self-contained
(it bundles its own Postgres + a relative `./init` bind-mount). That doesn't drop into **Compose Manager
Plus** when you already run Postgres and Caddy, because:

- the bundled Postgres duplicates your existing one,
- the `./init/...` relative bind-mount won't exist in CMP's per-stack project dir (Docker turns the
  missing path into an empty dir → the init never runs → Postgres init fails), and
- a private bridge network can't reach your `postgres18` on `shared_backend`.

Use [`compose-manager-plus.yaml`](compose-manager-plus.yaml) instead: no bundled Postgres, joins your
external networks, and points at `postgres18`.

## 1. Prepare Postgres (one-time)

Your `postgres18` already has pgvector (e.g. `pgvector/pgvector:pg18-trixie`). Create the database, a
least-privilege app role, the extension, and the fixed-dimension vector table by running
[`postgres-init.sql`](postgres-init.sql) **as a superuser**:

```bash
# edit the CHANGE_ME password first to match OM_PG_PASSWORD
docker exec -i postgres18 psql -v ON_ERROR_STOP=1 -U postgres < postgres-init.sql
```

Why the SQL: OpenMemory otherwise creates an unbounded `vector` column and then fails building an HNSW
index on it (upstream bug). Pre-creating the table at `vector(1536)` lets its idempotent
schema/index creation succeed. `1536` matches the default `synthetic` and OpenAI embeddings.

## 2. Find your Caddy network

```bash
docker inspect <your-caddy-container> --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
```

Put that name in `compose-manager-plus.yaml` → `networks.caddy.name`. (If Caddy is already on
`shared_backend`, you can drop the separate `caddy` network and put both services on `shared_backend`.)

## 3. Create the stack in Compose Manager Plus

1. **Add Stack** → name it `openmemory` → paste `compose-manager-plus.yaml`.
2. In the stack's `.env` (project dir `/boot/config/plugins/compose.manager/projects/openmemory/.env`),
   set:
   ```env
   OM_PG_PASSWORD=the-same-password-you-put-in-postgres-init.sql
   OM_API_KEY=run: openssl rand -hex 32
   # optional overrides: OM_PG_DB=openmemory  OM_PG_USER=openmemory
   ```
3. **Compose Up.** The two external networks (`shared_backend`, your Caddy network) must already exist.

## 4. Wire up Caddy (existing instance, public Let's Encrypt)

Add to your Caddyfile (replace the hostnames), then reload Caddy:

```caddy
# Backend API — protected by OM_API_KEY (send the x-api-key header).
memory-api.example.com {
    reverse_proxy openmemory:8080
}

# Dashboard UI. WARNING: the dashboard has NO built-in login — anyone who reaches
# this hostname can read/write your memories via its server-side proxy. Guard it:
memory.example.com {
    basic_auth {
        # generate: docker exec <caddy> caddy hash-password --plaintext 'yourpassword'
        you $2a$14$replace_with_a_real_bcrypt_hash
    }
    reverse_proxy openmemory-dashboard:3000
}
```

Prerequisites for public LE (HTTP challenge): public **DNS A/AAAA records** for both hostnames pointing
at your WAN IP, and ports **80 + 443** forwarded to Caddy. Caddy then auto-issues/renews certs. Caddy
resolves `openmemory` / `openmemory-dashboard` by name because they share its docker network.

> On Caddy older than v2.8 the directive is `basicauth` (no underscore). If you'd rather not expose the
> dashboard at all, omit its block and use only the API hostname.

## 5. Verify

```bash
curl https://memory-api.example.com/health                                  # public, no key
curl -H "x-api-key: $OM_API_KEY" https://memory-api.example.com/memory/all  # protected
# then open https://memory.example.com
```

## Notes

- **Architecture:** `openmemory` joins `shared_backend` (to reach `postgres18`) **and** your Caddy
  network (so Caddy + the dashboard can reach it). `dashboard` only needs the Caddy network.
- **Embedding dimension** is pinned to 1536 by the init SQL. Change embeddings → change the dim there and
  recreate the table.
- **Updating** OpenMemory: it tracks a pinned upstream commit; pull a newer `:latest` when this repo bumps
  `.upstream-commit`. `docker compose pull && up -d` (or CMP's update button).
