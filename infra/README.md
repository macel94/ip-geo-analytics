# Infrastructure as Code (Bicep)

This directory contains Bicep templates for deploying the IP Geo Analytics application to Azure Container Apps.

## Architecture

The deployment creates the following resources:

1. **Storage Account** (`ipgeoanalytics{environment}sa`)
   - Azure Files share for PostgreSQL data persistence
   - Standard LRS (locally redundant storage)
   - 1TB quota
   - Environment-specific naming (e.g., `ipgeoanalyticsstagingsa`, `ipgeoanalyticsproductionsa`)

2. **Container Apps Environment** (`ip-geo-analytics-{environment}-env`)
   - Hosts both PostgreSQL and application containers
   - Configured with Azure Files storage mount
   - Environment-specific (e.g., `ip-geo-analytics-staging-env`)

3. **PostgreSQL Container App** (`postgres`)
   - Image: `postgres:15-alpine`
   - Internal TCP ingress (port 5432)
   - Persistent volume mounted at `/var/lib/postgresql/data`
   - Scale: 0-1 replicas (scale-to-zero enabled)
   - Resources: 0.25 CPU, 0.5Gi memory

4. **Application Container App** (`app`)
   - Custom application image from GitHub Container Registry
   - External HTTPS ingress (port 3000)
   - Scale: 0-3 replicas (scale-to-zero enabled)
   - Resources: 0.25 CPU, 0.5Gi memory
   - Environment variables for database connection

## Deployment

### Via GitHub Actions (Recommended)

The deployment workflow is triggered on:
- Manual workflow dispatch (choose environment: staging or production)
- Git tags matching `v*` pattern

**Required GitHub Secrets:**
- `AZURE_CREDENTIALS` - Azure Service Principal credentials (JSON)
- `POSTGRES_PASSWORD` - PostgreSQL admin password (optional, defaults to 'analytics123' if not set)

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

## Outputs

| Output | Description |
|--------|-------------|
| `appUrl` | HTTPS URL of the deployed application |
| `storageAccountName` | Name of the storage account |
| `containerAppEnvName` | Name of the Container Apps environment |

## Cost Estimation

- **Container Apps**: Free tier includes 180k vCPU-seconds and 360k GiB-seconds per month
- **Storage**: ~$0.06/GB/month for Azure Files Standard LRS
- **Scale-to-zero**: Containers scale to 0 when idle, reducing costs

## Internal Networking

The PostgreSQL container app uses internal TCP ingress, making it accessible only within the Container Apps environment. The application connects using the hostname `postgres` on port `5432`.

## Data Persistence

PostgreSQL data is stored in Azure Files share (`pgdata`), ensuring data persists across:
- Container restarts
- Container updates
- Environment changes
- Scale-to-zero events

## Security Considerations

- PostgreSQL is not exposed to the internet (internal ingress only)
- Application uses HTTPS (Azure Container Apps automatic TLS)
- Container registry credentials stored as secrets
- Secure parameters used for sensitive data (passwords, tokens)
- Storage account uses TLS 1.2 minimum

## Troubleshooting

### View Container Logs

```bash
# Application logs
az containerapp logs show \
  --name app \
  --resource-group rg-ip-geo-analytics \
  --follow

# PostgreSQL logs
az containerapp logs show \
  --name postgres \
  --resource-group rg-ip-geo-analytics \
  --follow
```

### Check Deployment Status

```bash
az deployment group show \
  --resource-group rg-ip-geo-analytics \
  --name main \
  --query 'properties.{Status:provisioningState, Outputs:outputs}'
```

### Connect to PostgreSQL

```bash
# Get PostgreSQL FQDN (for internal connections only)
az containerapp show \
  --name postgres \
  --resource-group rg-ip-geo-analytics \
  --query 'properties.configuration.ingress.fqdn'
```
