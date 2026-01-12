# SRE Automation Guide

This document describes the SRE automation improvements added to the Visitor Analytics project.

## Overview

The project now includes comprehensive automation for:
- ✅ CI/CD pipelines
- ✅ Security scanning
- ✅ Monitoring and observability
- ✅ Infrastructure as Code (IaC)
- ✅ Operational automation scripts
- ✅ Incident response procedures

## Table of Contents

1. [CI/CD Pipelines](#cicd-pipelines)
2. [Security Automation](#security-automation)
3. [Monitoring & Observability](#monitoring--observability)
4. [Infrastructure as Code](#infrastructure-as-code)
5. [Automation Scripts](#automation-scripts)
6. [Quick Start](#quick-start)

---

## CI/CD Pipelines

### GitHub Actions Workflows

#### 1. E2E Tests (`.github/workflows/e2e-tests.yml`)
- **Trigger**: PR to main/master, push to main/master
- **Purpose**: Validate application functionality
- **Features**:
  - PostgreSQL service container
  - Database schema validation
  - Full stack integration testing
  - Test reports as artifacts

#### 2. Docker Build & Push (`.github/workflows/docker-build.yml`)
- **Trigger**: Push to main/master, tags, PRs
- **Purpose**: Build and publish container images
- **Features**:
  - Multi-platform builds
  - GitHub Container Registry (GHCR)
  - Build caching for faster builds
  - Trivy vulnerability scanning
  - SARIF upload to GitHub Security

#### 3. Security Scanning (`.github/workflows/security.yml`)
- **Trigger**: Push, PR, weekly schedule
- **Purpose**: Identify security vulnerabilities
- **Features**:
  - NPM audit for dependencies
  - TruffleHog secret scanning
  - CodeQL static analysis
  - Automated security reports

#### 4. Azure Deployment (`.github/workflows/deploy-azure.yml`)
- **Trigger**: Manual (workflow_dispatch), push to main, tags
- **Purpose**: Deploy to Azure Container Apps
- **Features**:
  - Infrastructure provisioning
  - Blue-green deployment support
  - Health check validation
  - Environment-based deployments (staging/production)

### Setting Up GitHub Actions

1. **Configure Secrets**:
   ```bash
   # Go to Settings > Secrets and variables > Actions
   # Add the following secrets:
   - AZURE_CREDENTIALS    # Azure service principal JSON
   - DB_PASSWORD          # Database password
   ```

2. **Azure Service Principal**:
   ```bash
   az ad sp create-for-rbac \
     --name "github-actions" \
     --role contributor \
     --scopes /subscriptions/{subscription-id}/resourceGroups/{resource-group} \
     --sdk-auth
   ```

3. **Enable GitHub Container Registry**:
   - Package is automatically published to `ghcr.io/macel94/ip-geo-analytics`
   - No additional configuration needed (uses GITHUB_TOKEN)

---

## Security Automation

### Dependabot (`.github/dependabot.yml`)

Automated dependency updates for:
- Root npm packages (weekly)
- Server dependencies (weekly)
- Client dependencies (weekly)
- GitHub Actions (weekly)
- Docker base images (weekly)

**Configuration**:
- Auto-labels PRs with `dependencies`, `automated`
- Limits to 10 open PRs per ecosystem
- Commits with `chore:` prefix

### Security Scanning

1. **Container Scanning** (Trivy):
   - Runs on every Docker build
   - Scans for CRITICAL and HIGH vulnerabilities
   - Results uploaded to GitHub Security tab

2. **Dependency Scanning** (npm audit):
   - Runs on every push/PR
   - Checks all workspaces
   - Continues on error (allows manual review)

3. **Secret Scanning** (TruffleHog):
   - Scans commit history
   - Detects hardcoded secrets
   - Only verified secrets trigger alerts

4. **SAST** (CodeQL):
   - Static analysis for JavaScript/TypeScript
   - Runs weekly + on push/PR
   - Detects security vulnerabilities and bugs

---

## Monitoring & Observability

### Application Endpoints

#### 1. Health Check (`/health`)
```bash
curl https://your-app.com/health
```
Response:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "database": "connected"
}
```

#### 2. Readiness Check (`/ready`)
```bash
curl https://your-app.com/ready
```
Response:
```json
{
  "status": "ready"
}
```

#### 3. Prometheus Metrics (`/metrics`)
```bash
curl https://your-app.com/metrics
```
Metrics exposed:
- `http_requests_total` - Total HTTP requests
- `tracking_requests_total` - Total tracking requests
- `http_errors_total` - Total errors
- `process_uptime_seconds` - Process uptime
- `nodejs_memory_usage_bytes` - Memory usage by type

### Azure Monitoring

The Bicep template includes:

1. **Log Analytics Workspace**:
   - 30-day retention
   - All application logs

2. **Application Insights**:
   - Request tracking
   - Exception tracking
   - Custom metrics
   - Performance monitoring

3. **Metric Alerts**:
   - High error rate (>10 errors in 5 min)
   - High memory usage (>900MB average)

### Setting Up Monitoring

1. **Configure Action Group**:
   Edit `deploy/main.bicep` to add email receivers:
   ```bicep
   emailReceivers: [
     {
       name: 'Admin'
       emailAddress: 'admin@example.com'
       useCommonAlertSchema: true
     }
   ]
   ```

2. **View Metrics** (Azure):
   ```bash
   az monitor metrics list \
     --resource <container-app-id> \
     --metric-names "Requests,Errors,WorkingSetBytes"
   ```

3. **Query Logs**:
   ```bash
   az monitor log-analytics query \
     --workspace <workspace-id> \
     --analytics-query "ContainerAppConsoleLogs_CL | where TimeGenerated > ago(1h)"
   ```

---

## Infrastructure as Code

### Azure Bicep (`deploy/main.bicep`)

Complete infrastructure including:
- PostgreSQL Flexible Server
- Container App Environment
- Container App with auto-scaling
- Log Analytics + Application Insights
- Metric alerts and action groups

**Deploy**:
```bash
cd deploy
./deploy.sh
```

**Enhanced Features**:
- Health probes (liveness/readiness)
- Auto-scaling (1-5 replicas based on concurrent requests)
- Integrated monitoring
- Automated alerting

### Kubernetes (`k8s/`)

Alternative deployment option with:

1. **Application** (`k8s/deployment.yaml`):
   - Deployment with 2+ replicas
   - HorizontalPodAutoscaler
   - Service + Ingress
   - Health/readiness probes
   - Resource limits

2. **Database** (`k8s/postgres.yaml`):
   - StatefulSet for PostgreSQL
   - PersistentVolumeClaim
   - Service for internal access

**Deploy to Kubernetes**:
```bash
kubectl apply -f k8s/postgres.yaml
kubectl apply -f k8s/deployment.yaml
```

---

## Automation Scripts

Located in `scripts/automation/`:

### 1. Database Backup (`backup-database.sh`)

Automated database backups with cloud storage support.

**Usage**:
```bash
# Local backup
export DATABASE_URL="postgresql://..."
./scripts/automation/backup-database.sh

# With Azure Blob Storage
export AZURE_STORAGE_ACCOUNT="mystorageaccount"
export AZURE_STORAGE_KEY="mykey"
./scripts/automation/backup-database.sh

# With AWS S3
export AWS_S3_BUCKET="my-backup-bucket"
./scripts/automation/backup-database.sh
```

**Features**:
- Compressed backups (gzip)
- Cloud upload (Azure Blob / AWS S3)
- Retention policy (7 days by default)
- Configurable via environment variables

**Schedule with Cron**:
```bash
# Daily at 2 AM
0 2 * * * /path/to/backup-database.sh >> /var/log/backup.log 2>&1
```

### 2. Health Check Monitor (`health-check.sh`)

Automated health monitoring with alerting.

**Usage**:
```bash
# Local check
./scripts/automation/health-check.sh

# With Slack alerts
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
export HEALTH_ENDPOINT="https://your-app.com/health"
./scripts/automation/health-check.sh

# Schedule with cron (every 5 minutes)
*/5 * * * * /path/to/health-check.sh
```

**Features**:
- Retries with exponential backoff
- Metrics extraction and analysis
- Slack/email alerting
- Error rate calculation

### 3. Load Testing (`load-test.sh`)

Performance testing with artillery.

**Usage**:
```bash
# Test local environment
./scripts/automation/load-test.sh http://localhost:3000

# Test production
./scripts/automation/load-test.sh https://your-app.com

# Custom rates
export WARM_UP_RATE=20
export SUSTAINED_RATE=100
export PEAK_RATE=200
./scripts/automation/load-test.sh https://your-app.com
```

**Features**:
- Configurable load patterns
- Multiple scenario testing
- HTML report generation
- Custom request rates

---

## Quick Start

### 1. Local Development with Automation

```bash
# Setup
./scripts/setup_local.sh

# Start services
./scripts/start_dev.sh

# In another terminal, run health check
./scripts/automation/health-check.sh

# Run load test
./scripts/automation/load-test.sh http://localhost:3000
```

### 2. Enable CI/CD

```bash
# 1. Configure GitHub secrets
gh secret set AZURE_CREDENTIALS < azure-credentials.json
gh secret set DB_PASSWORD

# 2. Push to trigger workflows
git add .
git commit -m "Enable automation"
git push

# 3. Monitor workflows
gh run list
gh run watch
```

### 3. Deploy to Azure

```bash
# 1. Login to Azure
az login

# 2. Set subscription
az account set --subscription "your-subscription-id"

# 3. Deploy infrastructure
cd deploy
./deploy.sh

# 4. Or use GitHub Actions
gh workflow run deploy-azure.yml -f environment=staging
```

### 4. Deploy to Kubernetes

```bash
# 1. Configure kubectl
kubectl config use-context my-cluster

# 2. Create namespace and secrets
kubectl create namespace visitor-analytics
kubectl create secret generic db-credentials \
  --from-literal=DATABASE_URL="postgresql://..." \
  -n visitor-analytics

# 3. Deploy
kubectl apply -f k8s/postgres.yaml
kubectl apply -f k8s/deployment.yaml

# 4. Check status
kubectl get pods -n visitor-analytics
kubectl get svc -n visitor-analytics
```

### 5. Set Up Monitoring

```bash
# 1. Get Application Insights connection string
az deployment group show \
  --resource-group rg-visitor-analytics \
  --name main \
  --query properties.outputs.appInsightsConnectionString.value

# 2. Configure Slack webhook for alerts
export SLACK_WEBHOOK_URL="your-webhook-url"
./scripts/automation/health-check.sh

# 3. Schedule health checks (cron)
crontab -e
# Add: */5 * * * * /path/to/health-check.sh
```

---

## Documentation

- **[SRE Runbook](./SRE_RUNBOOK.md)**: Operational procedures, troubleshooting, incident response
- **[Automation Details](./AUTOMATION.md)**: In-depth automation scripts and configurations
- **[Main README](../README.md)**: Project overview and getting started

---

## Best Practices

### Development
1. Always run tests before committing (`npm run test:e2e`)
2. Use the health check script to verify changes
3. Run load tests for performance-critical changes

### Deployment
1. Deploy to staging first
2. Run smoke tests after deployment
3. Monitor metrics for 24 hours
4. Have rollback plan ready

### Security
1. Never commit secrets
2. Review Dependabot PRs promptly
3. Check security scanning results
4. Rotate credentials quarterly

### Monitoring
1. Set up alerts for critical metrics
2. Review logs regularly
3. Monitor error rates
4. Track performance trends

---

## Troubleshooting

### CI/CD Issues

**Build failing?**
```bash
# Check workflow logs
gh run view --log

# Re-run failed jobs
gh run rerun <run-id>
```

**Container push failing?**
```bash
# Check GITHUB_TOKEN permissions
# Ensure packages:write permission is granted
```

### Monitoring Issues

**No metrics appearing?**
- Verify `/metrics` endpoint is accessible
- Check Application Insights connection string
- Review Log Analytics workspace configuration

**Alerts not firing?**
- Verify action group configuration
- Check alert rule conditions
- Review metric data in Azure Monitor

### Deployment Issues

**Container app not starting?**
```bash
# Check logs
az containerapp logs show \
  --name <app-name> \
  --resource-group rg-visitor-analytics \
  --follow

# Check environment variables
az containerapp show \
  --name <app-name> \
  --resource-group rg-visitor-analytics \
  --query properties.template.containers[0].env
```

---

## Next Steps

Consider adding:
1. **Performance monitoring** with custom metrics
2. **Distributed tracing** with OpenTelemetry
3. **Cost monitoring** and optimization
4. **Chaos engineering** experiments
5. **GitOps** with ArgoCD or Flux
6. **Service mesh** for advanced traffic management
7. **Multi-region deployment** for HA
8. **Disaster recovery** automation

---

## Support

For issues or questions:
1. Check the [SRE Runbook](./SRE_RUNBOOK.md)
2. Review [GitHub Issues](https://github.com/macel94/ip-geo-analytics/issues)
3. Check workflow logs in GitHub Actions
4. Review Azure Monitor logs
