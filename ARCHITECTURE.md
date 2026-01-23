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
│  │              │  │   Azure/K8s  │  │              │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Container Registry (GHCR)                     │
│              ghcr.io/macel94/ip-geo-analytics:latest            │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌───────────────────────────┐   ┌───────────────────────────┐
│   Azure Container Apps    │   │       Kubernetes          │
│  ┌─────────────────────┐  │   │  ┌─────────────────────┐  │
│  │  Container App      │  │   │  │   Deployment        │  │
│  │  ┌───────────────┐  │  │   │  │  ┌───────────────┐  │  │
│  │  │ Application   │  │  │   │  │  │ Pods (2-10)   │  │  │
│  │  │ ┌──────────┐  │  │  │   │  │  │ ┌──────────┐  │  │  │
│  │  │ │ /health  │  │  │  │   │  │  │ │ /health  │  │  │  │
│  │  │ │ /ready   │  │  │  │   │  │  │ │ /ready   │  │  │  │
│  │  │ │ /metrics │  │  │  │   │  │  │ │ /metrics │  │  │  │
│  │  │ │ /api/*   │  │  │  │   │  │  │ │ /api/*   │  │  │  │
│  │  │ └──────────┘  │  │  │   │  │  │ └──────────┘  │  │  │
│  │  └───────────────┘  │  │   │  │  └───────────────┘  │  │
│  │  Auto-scaling 1-5   │  │   │  │  HPA (2-10)         │  │
│  └─────────────────────┘  │   │  └─────────────────────┘  │
│                           │   │                           │
│  ┌─────────────────────┐  │   │  ┌─────────────────────┐  │
│  │ Log Analytics       │  │   │  │  Service + Ingress  │  │
│  └─────────────────────┘  │   │  └─────────────────────┘  │
│  ┌─────────────────────┐  │   └───────────────────────────┘
│  │ App Insights        │  │
│  └─────────────────────┘  │
│  ┌─────────────────────┐  │
│  │ Metric Alerts       │  │
│  └─────────────────────┘  │
└───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      PostgreSQL Database                         │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Azure PostgreSQL Flexible Server / K8s StatefulSet       │  │
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
│     ├─ Deploy Bicep infrastructure         │
│     ├─ Update Container App                │
│     ├─ Verify health check                 │
│     └─ Send notification                   │
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
│  ├─ Dropped capabilities                    │
│  └─ Network policies (K8s)                  │
└─────────────────────────────────────────────┘
```

## Deployment Options

### Azure Container Apps
```
┌──────────────────────────────────────┐
│   Azure Resource Group               │
│  ┌────────────────────────────────┐  │
│  │  Container App Environment     │  │
│  │  ┌──────────────────────────┐  │  │
│  │  │  Container App           │  │  │
│  │  │  - Min: 1 replica        │  │  │
│  │  │  - Max: 5 replicas       │  │  │
│  │  │  - Scale: 50 req/replica │  │  │
│  │  └──────────────────────────┘  │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │  PostgreSQL Flexible Server    │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │  Log Analytics Workspace       │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │  Application Insights          │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │  Action Group + Alerts         │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

### Kubernetes
```
┌──────────────────────────────────────┐
│   Namespace: visitor-analytics       │
│  ┌────────────────────────────────┐  │
│  │  Deployment                    │  │
│  │  - Replicas: 2                 │  │
│  │  - Health probes               │  │
│  │  - Resource limits             │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │  HorizontalPodAutoscaler       │  │
│  │  - Min: 2, Max: 10             │  │
│  │  - CPU: 70%, Memory: 80%       │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │  Service (ClusterIP)           │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │  Ingress (nginx)               │  │
│  │  - TLS termination             │  │
│  │  - cert-manager                │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │  PostgreSQL StatefulSet        │  │
│  │  - PVC: 10Gi                   │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
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
| IaC (Azure) | Infrastructure provisioning | `deploy/main.bicep` |
| IaC (K8s) | Kubernetes deployment | `k8s/*.yaml` |
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
- Kubernetes (alternative deployment)
- GitHub Actions (CI/CD)

**Monitoring:**
- Prometheus metrics format
- Azure Application Insights
- Custom health checks
- Log Analytics

**Security:**
- Trivy (container scanning)
- CodeQL (SAST)
- TruffleHog (secret scanning)
- npm audit (dependency scanning)
- Dependabot (automated updates)
