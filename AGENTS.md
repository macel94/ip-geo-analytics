# AI Agent Context & Guidelines (`AGENTS.md`)

This file contains context, architectural decisions, and coding standards for AI agents working on the **Visitor Analytics** project.

## 1. Project Overview
A lightweight visitor analytics platform designed for personal use and low-volume traffic. It tracks HTTP request metadata (IP, Referrer, User-Agent) and aggregates it into a dashboard.

**Key Constraints:**
-   **No Next.js**. Pure React (Vite) + Fastify (Node.js).
-   **Hosting**: Azure Container Apps (Dockerized).
-   **Database**: PostgreSQL (via Prisma).
-   **Privacy**: Technical demo only (no GDPR/Consent implementation required).

## 2. Tech Stack Verification
-   **Backend**: Node.js, Fastify, Prisma ORM, `@maxmind/geoip2-node`.
-   **Frontend**: React, Vite, Leaflet (`react-leaflet`), Chart.js.
-   **Infra**: Docker, Docker Compose (local), Azure Bicep (cloud).

## 3. High-Level Architecture
-   **Monorepo**:
    -   `/server`: Backend API.
    -   `/client`: Frontend SPA.
    -   `/deploy`: IaC and deployment scripts.
-   **IP Handling**:
    -   Must use `trustProxy: true` in Fastify configuration to handle Azure Load Balancers.
    -   GeoIP lookups should use a Singleton pattern to avoid reloading the MMDB file on every request.
-   **Data Flow**:
    -   `POST /api/track` -> Fastify -> GeoIP Lookup -> Prisma Write.
    -   `GET /api/stats` -> Prisma Aggregation -> JSON Response -> React Dashboard.

## 4. Coding Standards
-   **TypeScript**: Strict mode enabled. Define interfaces for all API payloads and Database models.
-   **Async/Await**: Prefer `async/await` over raw Promises.
-   **Error Handling**: Wrap controller logic in `try/catch` and return standard HTTP 500 responses on failure.
-   **Environment Variables**:
    -   Access via `process.env`.
    -   Fail fast if critical variables (`DATABASE_URL`) are missing.

## 5. Development Workflow
-   **Scripts**: Always prefer using the scripts in `/scripts/` over raw npm commands.
    -   `./scripts/setup_local.sh`: Full initialization.
    -   `./scripts/start_dev.sh`: Concurrent dev servers.
-   **Database**:
    -   Schema changes go in `server/prisma/schema.prisma`.
    -   Run `npx prisma db push` (or the setup script) to apply changes locally.

## 6. Known "Gotchas"
-   **GeoIP Database**: The `.mmdb` file is expected at a specific path. Ensure the code checks for its existence before crashing, or simply warns.
-   **Azure Ingress**: The Dockerfile builds both client and server. The Server serves the static client files in production. In development, they run on separate ports (3000 vs 5173).
