# Infrastructure as Code (Bicep)

This directory contains Bicep templates for deploying the IP Geo Analytics application to Azure Container Apps.

## Architecture

The deployment creates the following resources:

1. **Storage Account** (`ipgeoanalytics{environment}sa`)
   - Azure Files share for PostgreSQL data persistence
   - Standard LRS (locally redundant storage)
   - 1TB quota
   - Environment-specific naming (e.g., `ipgeoanalyticsstagingsa`, `ipgeoanalyticsproductionsa`)

2. **Log Analytics Workspace** (`ip-geo-analytics-{environment}-logs`)
   - Centralized logging for Container Apps
   - Configurable retention (30-730 days)
   - Used by both Container Apps environment and Application Insights

3. **Application Insights** (`ip-geo-analytics-{environment}-appinsights`)
   - Application monitoring and telemetry
   - Connected to Log Analytics workspace for log aggregation
   - Connection string passed to app container for SDK integration

4. **Container Apps Environment** (`ip-geo-analytics-{environment}-env`)
   - Hosts both PostgreSQL and application containers
   - Configured with Azure Files storage mount
   - Log Analytics integration for container logs
   - Environment-specific (e.g., `ip-geo-analytics-staging-env`)

5. **PostgreSQL Container App** (`postgres`)
   - Image: `postgres:15-alpine`
   - Internal TCP ingress (port 5432)
   - Persistent volume mounted at `/var/lib/postgresql/data`
   - **Scale: 1-1 replicas (always running)** - Required because TCP connections cannot wake scaled-to-zero containers
   - Resources: 0.25 CPU, 0.5Gi memory
   - Health probes:
     - TCP Liveness probe (port 5432, every 10s)
     - TCP Readiness probe (port 5432, every 5s)

6. **Application Container App** (`app`)
   - Custom application image from GitHub Container Registry
   - External HTTPS ingress (port 3000)
   - Scale: 0-3 replicas (scale-to-zero enabled)
   - Resources: 0.25 CPU, 0.5Gi memory
   - Environment variables for database connection and Application Insights
   - Health probes:
     - HTTP Startup probe (`/health`, allows 2.5 min startup for migrations)
     - HTTP Liveness probe (`/health`, every 30s)
     - HTTP Readiness probe (`/ready`, every 10s)

## Deployment

### Pull Request Validation

When you open a PR that modifies infrastructure files, the **Validate Bicep Infrastructure** workflow automatically runs:

1. **Syntax validation**: Ensures Bicep code compiles without errors
2. **What-if analysis**: Shows what resources would be created, modified, or deleted
3. **PR comment**: Posts a summary of changes directly on the PR

This allows you to review infrastructure changes before merging and deploying.

**Triggered by changes to**:
- `infra/**` (any Bicep files)
- `.github/workflows/deploy-azure-container-apps.yml`
- `.github/workflows/validate-bicep.yml`

### Via GitHub Actions (Recommended)

The deployment workflow is triggered on:
- Manual workflow dispatch (choose environment: staging or production)
- Git tags matching `v*` pattern

**Required GitHub Secrets:**
- `AZURE_CREDENTIALS` - Azure Service Principal credentials (JSON)
- `POSTGRES_PASSWORD` - PostgreSQL admin password (recommended for production, defaults to 'analytics123' for demo/staging)

> **⚠️ Security Note**: For production deployments, always set `POSTGRES_PASSWORD` as a GitHub secret with a strong, unique password. The default is only provided for demo and development convenience.

```bash
# Tag-based deployment
git tag v1.0.0
git push origin v1.0.0
```

### Manual Deployment

Prerequisites:
- Azure CLI installed
- Logged in to Azure (`az login`)
- GitHub Container Registry credentials

```bash
# Create resource group
az group create \
  --name rg-ip-geo-analytics \
  --location eastus

# Deploy infrastructure
az deployment group create \
  --resource-group rg-ip-geo-analytics \
  --template-file infra/main.bicep \
  --parameters \
    location=eastus \
    environment=staging \
    imageTag=ghcr.io/macel94/ip-geo-analytics:sha-abc123 \
    registryServer=ghcr.io \
    registryUsername=your-username \
    registryPassword=your-pat-token \
    postgresPassword=your-secure-password
```

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `location` | string | No | Resource group location | Azure region for resources |
| `environment` | string | No | `staging` | Environment name (staging/production) |
| `imageTag` | string | Yes | - | Full container image tag |
| `registryServer` | string | No | `ghcr.io` | Container registry server |
| `registryUsername` | string | Yes | - | Container registry username |
| `registryPassword` | string | Yes | - | Container registry password/PAT |
| `postgresPassword` | string | Yes | - | PostgreSQL admin password |
| `logRetentionDays` | int | No | `30` | Log Analytics retention in days (30-730) |

## Outputs

| Output | Description |
|--------|-------------|
| `appUrl` | HTTPS URL of the deployed application |
| `storageAccountName` | Name of the storage account |
| `containerAppEnvName` | Name of the Container Apps environment |
| `appInsightsConnectionString` | Application Insights connection string |
| `appInsightsInstrumentationKey` | Application Insights instrumentation key |
| `logAnalyticsWorkspaceId` | Log Analytics workspace resource ID |

## Cost Estimation

- **Container Apps**: Free tier includes 180k vCPU-seconds and 360k GiB-seconds per month
- **Storage**: ~$0.06/GB/month for Azure Files Standard LRS
- **Log Analytics**: Free tier includes 5GB/month ingestion
- **Application Insights**: First 5GB/month free
- **Scale-to-zero**: App container scales to 0 when idle, reducing costs
- **Note**: PostgreSQL must run with minReplicas=1 because TCP connections cannot wake scaled-to-zero containers

## Internal Networking

The PostgreSQL container app uses internal TCP ingress, making it accessible only within the Container Apps environment. The application connects using the hostname `postgres` on port `5432`.

## Data Persistence

PostgreSQL data is stored in Azure Files share (`pgdata`), ensuring data persists across:
- Container restarts
- Container updates
- Environment changes
- Scale-to-zero events

## Security Considerations

- PostgreSQL is not exposed to the internet (internal TCP ingress only)
- Application uses HTTPS (Azure Container Apps automatic TLS)
- Container registry credentials stored as secrets in Bicep
- Secure parameters used for sensitive data (passwords, tokens)
- Storage account uses TLS 1.2 minimum

### Database Security

The PostgreSQL password is passed as an environment variable in the DATABASE_URL. While this is acceptable for this demo project because:
1. PostgreSQL has internal-only ingress (not exposed to internet)
2. Container Apps environment provides network isolation
3. Only the app container can connect to PostgreSQL

For enhanced security in production:
- Consider using Azure Key Vault for secrets
- Use managed identities where possible
- Rotate passwords regularly
- Enable audit logging

## Troubleshooting

### View Container Logs

```bash
# Application logs (stream)
az containerapp logs show \
  --name app \
  --resource-group rg-ip-geo-analytics \
  --follow

# PostgreSQL logs (stream)
az containerapp logs show \
  --name postgres \
  --resource-group rg-ip-geo-analytics \
  --follow

# View system logs (including health probe failures)
az containerapp logs show \
  --name app \
  --resource-group rg-ip-geo-analytics \
  --type system
```

### Check Container Revision Status

```bash
# Check if containers are running and healthy
az containerapp revision list \
  --name app \
  --resource-group rg-ip-geo-analytics \
  --query '[].{Name:name,Active:active,Replicas:replicas,Health:healthState,Created:createdTime}' \
  -o table

az containerapp revision list \
  --name postgres \
  --resource-group rg-ip-geo-analytics \
  --query '[].{Name:name,Active:active,Replicas:replicas,Health:healthState,Created:createdTime}' \
  -o table
```

### Check Deployment Status

```bash
az deployment group show \
  --resource-group rg-ip-geo-analytics \
  --name main \
  --query 'properties.{Status:provisioningState, Outputs:outputs}'
```

### View Application Insights Logs

```bash
# Get Application Insights connection string
az deployment group show \
  --resource-group rg-ip-geo-analytics \
  --name main \
  --query 'properties.outputs.appInsightsConnectionString.value' -o tsv

# Or view logs in Azure Portal:
# 1. Go to Azure Portal -> Application Insights -> ip-geo-analytics-{env}-appinsights
# 2. Click "Logs" in the left menu
# 3. Query: traces | order by timestamp desc | take 100
```

### Common Issues

**Containers not starting:**
1. Check revision status (see above)
2. Check system logs for health probe failures
3. Verify PostgreSQL is running (minReplicas=1 is required)
4. Check if image exists in GitHub Container Registry

**Database connection failures:**
1. Ensure PostgreSQL container is running: `az containerapp revision list --name postgres -g rg-ip-geo-analytics`
2. Check PostgreSQL logs for startup errors
3. Verify DATABASE_URL format is correct

**No logs in Application Insights:**
1. Verify APPLICATIONINSIGHTS_CONNECTION_STRING is set
2. Check app container logs for Application Insights SDK errors
3. Allow 2-5 minutes for logs to appear after container startup

### Connect to PostgreSQL

```bash
# Get PostgreSQL FQDN (for internal connections only)
az containerapp show \
  --name postgres \
  --resource-group rg-ip-geo-analytics \
  --query 'properties.configuration.ingress.fqdn'
```
