# The project is small, but the workflow is full-stack

<div class="grid grid-cols-2 gap-8 mt-8">
<div>

## Application

- `client/` → React + Vite dashboard
- `server/` → Fastify + Prisma API
- `docker-compose.yml` → local PostgreSQL 18
- `Dockerfile` → production image for the app

</div>
<div>

## Delivery path

- `.devcontainer/devcontainer.json` standardizes local tooling
- `.github/workflows/e2e-tests.yml` validates the app continuously
- `infra/main.bicep` defines Azure Container Apps + storage
- `.github/workflows/deploy-azure-container-apps.yml` deploys the same image

</div>
</div>

## Why containers matter here

Without containers, every step would drift: editor setup, database setup, browser dependencies, and deployment runtime.

<!--
Source anchors:
- .devcontainer/devcontainer.json
- docker-compose.yml
- Dockerfile
- .github/workflows/e2e-tests.yml
- infra/main.bicep
-->
