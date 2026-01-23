# Architecture Overview

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          GitHub Actions                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  E2E Tests   │  │Docker Build  │  │  Security    │          │
│  │              │  │   + Push     │  │   Scanning   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Dependabot  │  │   Deploy     │  │   CodeQL     │          │
│  │              │  │ Azure ACA    │  │              │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Container Registry (GHCR)                     │
│              ghcr.io/macel94/ip-geo-analytics:latest            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Container Apps                          │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Container App Environment                                 │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  Container App (scale to zero enabled)              │  │  │
│  │  │  ┌───────────────────────────────────────────────┐  │  │  │
│  │  │  │ Application                                   │  │  │  │
│  │  │  │ ┌──────────┐ ┌──────────┐ ┌──────────┐       │  │  │  │
│  │  │  │ │ /health  │ │ /ready   │ │ /metrics │       │  │  │  │
│  │  │  │ └──────────┘ └──────────┘ └──────────┘       │  │  │  │
│  │  │  │ ┌──────────┐ ┌──────────┐                    │  │  │  │
│  │  │  │ │ /api/*   │ │ Static   │                    │  │  │  │
│  │  │  │ └──────────┘ └──────────┘                    │  │  │  │
│  │  │  └───────────────────────────────────────────────┘  │  │  │
│  │  │  Auto-scaling: 0-3 replicas                         │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      PostgreSQL Database                         │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Azure PostgreSQL Flexible Server                         │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐                   │  │
│  │  │ Visits  │  │ Backups │  │ Metrics │                   │  │
│  │  └─────────┘  └─────────┘  └─────────┘                   │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

```
┌──────────┐
│  Client  │
│ Browser  │
└────┬─────┘
     │ HTTP Request
     ▼
┌─────────────────┐
│  Load Balancer  │
│  / Ingress      │
└────┬────────────┘
     │
     ▼
┌──────────────────────────────────┐
│      Application Server          │
│                                  │
│  1. /health check                │
│     ├─ Database ping             │
│     └─ Return status             │
│                                  │
│  2. /ready check                 │
│     └─ Database ping             │
│                                  │
│  3. /metrics                     │
│     ├─ Request counter           │
│     ├─ Error counter             │
│     ├─ Memory stats              │
│     └─ Uptime                    │
│                                  │
│  4. /api/track                   │
│     ├─ Extract IP                │
│     ├─ GeoIP lookup              │
│     ├─ Parse User-Agent          │
│     ├─ Save to database          │
│     └─ Increment metrics         │
│                                  │
│  5. /api/stats                   │
│     ├─ Query database            │
│     ├─ Aggregate data            │
│     └─ Return JSON               │
└──────────┬───────────────────────┘
           │
           ▼
┌──────────────────────┐
│   PostgreSQL DB      │
│  ┌────────────────┐  │
│  │  visits table  │  │
│  │  - ip_address  │  │
│  │  - city        │  │
│  │  - country     │  │
│  │  - browser     │  │
│  │  - device      │  │
│  │  - referrer    │  │
│  └────────────────┘  │
└──────────────────────┘
```

## Monitoring & Alerting Flow

```
┌─────────────────┐
│  Application    │
│  /metrics       │──────┐
└─────────────────┘      │
                         │
┌─────────────────┐      │    ┌──────────────────┐
│  Application    │      ├───▶│   Prometheus     │
│  Logs           │──────┘    │   (optional)     │
└─────────────────┘           └────────┬─────────┘
                                       │
┌─────────────────┐                    │
│  Health Check   │                    ▼
│  Script (cron)  │           ┌──────────────────┐
└────────┬────────┘           │   Grafana        │
         │                    │   (optional)     │
         │ Alert              └──────────────────┘
         ▼
┌─────────────────┐
│  Slack Webhook  │
│  Email Alert    │
└─────────────────┘

┌─────────────────────────────────────────┐
│      Azure Application Insights          │
│  ┌─────────────────────────────────┐    │
│  │  Automatic Telemetry            │    │
│  │  - Requests                     │    │
│  │  - Dependencies                 │    │
│  │  - Exceptions                   │    │
│  │  - Custom Events                │    │
│  └─────────────────────────────────┘    │
│                                          │
│  ┌─────────────────────────────────┐    │
│  │  Metric Alerts                  │    │
│  │  - High Error Rate              │    │
│  │  - High Memory Usage            │    │
│  └────────────┬────────────────────┘    │
└───────────────┼─────────────────────────┘
                │
                ▼
       ┌─────────────────┐
       │  Action Group   │
       │  - Email        │
       │  - SMS          │
       │  - Webhook      │
       └─────────────────┘
```

## CI/CD Pipeline Flow

```
┌──────────────┐
│  Git Push    │
└──────┬───────┘
       │
       ▼
┌────────────────────────────────────────────┐
│         GitHub Actions Triggers            │
├────────────────────────────────────────────┤
│  1. E2E Tests                              │
│     ├─ Start PostgreSQL container          │
│     ├─ Install dependencies                │
│     ├─ Run migrations                      │
│     ├─ Build client                        │
│     ├─ Run Playwright tests                │
│     └─ Upload test reports                 │
│                                            │
│  2. Security Scanning                      │
│     ├─ npm audit (all workspaces)          │
│     ├─ TruffleHog (secrets)                │
│     ├─ CodeQL (SAST)                       │
│     └─ Upload results to Security tab      │
│                                            │
│  3. Docker Build                           │
│     ├─ Build multi-stage image             │
│     ├─ Run Trivy scan                      │
│     ├─ Push to GHCR                        │
│     └─ Upload SARIF to Security            │
│                                            │
│  4. Deploy (manual or on tag)              │
│     ├─ Create Azure Container Apps env     │
│     ├─ Deploy via docker-compose           │
│     ├─ Configure ingress & scaling         │
│     └─ Verify health check                 │
└────────────────────────────────────────────┘
```

## Automation Scripts Flow

```
┌─────────────────────────────────────┐
│      Cron Jobs / Scheduled Tasks    │
├─────────────────────────────────────┤
│                                     │
│  Daily (2 AM)                       │
│  ┌────────────────────────┐         │
│  │  backup-database.sh    │         │
│  │  ├─ pg_dump            │         │
│  │  ├─ gzip compress      │         │
│  │  ├─ Upload to cloud    │         │
│  │  └─ Cleanup old files  │         │
│  └────────────────────────┘         │
│                                     │
│  Every 5 minutes                    │
│  ┌────────────────────────┐         │
│  │  health-check.sh       │         │
│  │  ├─ HTTP GET /health   │         │
│  │  ├─ Check metrics      │         │
│  │  ├─ Calculate rates    │         │
│  │  └─ Alert if needed    │         │
│  └────────────────────────┘         │
│                                     │
│  On-demand                          │
│  ┌────────────────────────┐         │
│  │  load-test.sh          │         │
│  │  ├─ Artillery setup    │         │
│  │  ├─ Run scenarios      │         │
│  │  └─ Generate report    │         │
│  └────────────────────────┘         │
└─────────────────────────────────────┘
```

## Security Layers

```
┌─────────────────────────────────────────────┐
│           Security Scanning Layers          │
├─────────────────────────────────────────────┤
│  Layer 1: Source Code                       │
│  ├─ CodeQL (SAST)                           │
│  ├─ TruffleHog (Secrets)                    │
│  └─ ESLint / TSLint (optional)              │
│                                             │
│  Layer 2: Dependencies                      │
│  ├─ npm audit                               │
│  ├─ Dependabot                              │
│  └─ GitHub Security Advisories              │
│                                             │
│  Layer 3: Container Images                  │
│  ├─ Trivy (vulnerabilities)                 │
│  ├─ Base image scanning                     │
│  └─ SARIF upload to GitHub                  │
│                                             │
│  Layer 4: Runtime                           │
│  ├─ Non-root containers                     │
│  ├─ Read-only filesystem (where possible)   │
│  └─ Dropped capabilities                    │
└─────────────────────────────────────────────┘
```

## Deployment Architecture

### Azure Container Apps (Individual Container Deployment)
```
┌──────────────────────────────────────────────────┐
│   Azure Resource Group (rg-ip-geo-analytics)     │
│  ┌────────────────────────────────────────────┐  │
│  │  Azure Storage Account                     │  │
│  │  └─ Azure Files Share (pgdata)             │  │
│  └────────────────────────────────────────────┘  │
│                       │                          │
│                       ▼                          │
│  ┌────────────────────────────────────────────┐  │
│  │  Container Apps Environment                │  │
│  │  (ip-geo-analytics-env)                    │  │
│  │  ┌──────────────────────────────────────┐  │  │
│  │  │  Container App (app)                 │  │  │
│  │  │  - Min: 0 replicas (scale to zero)   │  │  │
│  │  │  - Max: 3 replicas                   │  │  │
│  │  │  - Image: ghcr.io/macel94/           │  │  │
│  │  │          ip-geo-analytics:latest     │  │  │
│  │  │  - Health probes: /health, /ready    │  │  │
│  │  │  - External ingress (HTTPS)          │  │  │
│  │  └──────────────────────────────────────┘  │  │
│  │                    │                       │  │
│  │                    ▼                       │  │
│  │  ┌──────────────────────────────────────┐  │  │
│  │  │  Container App (postgres)            │  │  │
│  │  │  - 1 replica (always on)             │  │  │
│  │  │  - Image: postgres:15-alpine         │  │  │
│  │  │  - Internal ingress (TCP)            │  │  │
│  │  │  - Azure Files volume mounted        │  │  │
│  │  └──────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘

Deployment via: az containerapp create (individual containers)
Config file: docker-compose.azure.yml (reference documentation)
```

## Key Components Summary

| Component | Purpose | Location |
|-----------|---------|----------|
| Health Check | Liveness probe | `/health` |
| Readiness Check | Ready to serve traffic | `/ready` |
| Metrics | Prometheus metrics | `/metrics` |
| Tracking API | Record visitor data | `/api/track` |
| Stats API | Retrieve analytics | `/api/stats` |
| CI/CD | Automated testing & deployment | `.github/workflows/` |
| Deployment | Azure Container Apps | `docker-compose.azure.yml` |
| Automation | Operational scripts | `scripts/automation/` |
| Documentation | SRE guides | `docs/` |

## Technology Stack

**Frontend:**
- React 19
- Vite 5
- Leaflet (maps)
- Chart.js (charts)

**Backend:**
- Node.js 24
- Fastify 5
- Prisma 7
- PostgreSQL 15

**Infrastructure:**
- Docker (containerization)
- Azure Container Apps (cloud deployment)
- GitHub Actions (CI/CD)

**Monitoring:**
- Prometheus metrics format
- Custom health checks

**Security:**
- Trivy (container scanning)
- CodeQL (SAST)
- TruffleHog (secret scanning)
- npm audit (dependency scanning)
- Dependabot (automated updates)
