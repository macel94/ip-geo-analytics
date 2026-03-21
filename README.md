# ip-geo-analytics

A small visitor analytics demo built with Fastify, Prisma, PostgreSQL, React, and Vite.

## What it does

- tracks visits with IP, user-agent, referrer, and GeoIP metadata
- exposes aggregated analytics through a dashboard
- runs locally with Docker Compose
- ships as a container and deploys to Azure Container Apps

## Quick start

```bash
./scripts/setup_local.sh
./scripts/start_dev.sh
```

App URLs:
- Frontend: http://localhost:5173
- Backend: http://localhost:3000

## Testing

```bash
npm run test:setup
npm run test:e2e
```

## Technical talk slides

The presentation material lives in `docs/` as a Slidev project.

```bash
npm run docs:dev
npm run docs:build
```

## Key files

- `.devcontainer/devcontainer.json` — development container setup
- `docker-compose.yml` — local PostgreSQL container
- `Dockerfile` — production image build
- `.github/workflows/e2e-tests.yml` — Playwright E2E workflow
- `infra/main.bicep` — Azure Container Apps infrastructure
- `.github/workflows/deploy-azure-container-apps.yml` — deployment workflow

## Environment

`./scripts/setup_local.sh` creates `server/.env` with a local `DATABASE_URL` if it is missing.

For GeoIP lookups, place `GeoLite2-City.mmdb` at `server/geoip/GeoLite2-City.mmdb` for local development.
