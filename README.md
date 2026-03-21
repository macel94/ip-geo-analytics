# ip-geo-analytics

Visitor analytics demo built with Fastify, Prisma, PostgreSQL, React, and Vite.

## Quick start

```bash
npm run setup
npm run dev
```

- API: http://localhost:3000
- Web: http://localhost:5173

## What’s here

- `server/` — Fastify + Prisma API
- `client/` — React dashboard
- `infra/` — Azure Container Apps Bicep templates
- `docs/` — Slidev technical talk about the project’s container story

## Useful commands

```bash
npm run setup
npm run dev
npm run test:setup
npm run test:e2e
npm run docs:dev
npm run docs:build
```

## Container story

This project leans on containers at every stage:

- a Dev Container for a consistent local development environment
- Docker Compose for local PostgreSQL
- a single production image built from the root `Dockerfile`
- Playwright-driven E2E validation in CI
- Azure Container Apps for deployment, scale-to-zero, and persistent PostgreSQL storage

## Deployment

Infrastructure lives in [`infra/main.bicep`](infra/main.bicep). See [`infra/README.md`](infra/README.md) for Azure deployment details.
