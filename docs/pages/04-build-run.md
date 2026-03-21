# We containerized both local state and the production app

## Local state with Compose

- `docker-compose.yml` runs `postgres:18-alpine`
- named volume `postgres_data` keeps local data between restarts
- health checks let scripts wait for a ready database

## Production packaging with Docker

- multi-stage `Dockerfile`
- Vite client is built separately from the TypeScript server
- final image contains the built SPA, compiled server, Prisma artifacts, and GeoIP DB
- container start runs `prisma db push` before booting Fastify

## Why this helped

One image becomes the deployable unit instead of a checklist of manual steps.

```text
source -> build client -> build server -> assemble runtime image -> deploy same artifact
```

<!--
Source: docker-compose.yml, docker-compose.azure.yml, Dockerfile
The point to emphasize: containers made local and production packaging converge.
-->
