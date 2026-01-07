# ip-geo-analytics

Visitor analytics demo (Fastify + Prisma + React/Vite) that records IP, User-Agent, referrer, and GeoIP data, then surfaces aggregates (map + charts).

## Stack

- Fastify 5, Prisma 7, PostgreSQL
- React 18 + Vite 5, Leaflet, Chart.js
- Docker/Docker Compose; Dev Container (Node 24) for local dev

## Quick Start (local)

```bash
# from repo root
./scripts/setup_local.sh   # installs deps, starts Postgres via docker-compose, prisma db push
./scripts/start_dev.sh     # runs Fastify (3000) + Vite (5173)
```

## Environment

- `server/.env` is created by setup with `DATABASE_URL` pointing to local Postgres.
- GeoIP: place `GeoLite2-City.mmdb` at `server/geoip/GeoLite2-City.mmdb` (or adjust path in [server/src/services/geoip.ts](server/src/services/geoip.ts)).

## Prisma 7 notes

- Datasource URL now lives in [server/prisma/prisma.config.ts](server/prisma/prisma.config.ts); `schema.prisma` no longer contains `url`.
- Prisma Client instantiation passes `datasourceUrl` (see [server/src/index.ts](server/src/index.ts)).
- Helpful commands (from `server/`):
  - `npx prisma validate`
  - `npx prisma format`
  - `npx prisma generate`
  - `npx prisma migrate status`
  - `npx prisma db push` (for dev sync)

## Scripts

- `./scripts/setup_local.sh` — one-time/local bootstrap (deps, db, env, db push)
- `./scripts/start_dev.sh` — concurrent dev servers (Fastify + Vite)

## Docker

The root [Dockerfile](Dockerfile) builds client and server into a single image (Node 24 Alpine). In prod the Fastify server serves the built SPA.

## Deployment (Azure)

- Bicep template: [deploy/main.bicep](deploy/main.bicep)
- Script: [deploy/deploy.sh](deploy/deploy.sh)

## Current ports

- API: 3000
- Web: 5173
- Postgres: 5432
