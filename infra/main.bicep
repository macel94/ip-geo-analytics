// Main deployment template for IP Geo Analytics infrastructure

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (staging or production)')
param environment string = 'staging1'

@description('Container image tag')
param imageTag string

@description('Container registry server')
param registryServer string = 'ghcr.io'

@description('Container registry username')
@secure()
param registryUsername string

@description('Container registry password')
@secure()
param registryPassword string

@description('PostgreSQL admin password')
@secure()
param postgresPassword string

@description('Log Analytics retention in days (30-730)')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

// Variables
var storageAccountName = 'ipgeoanalytics${environment}sa'
var storageShareName = 'pgdata'
var containerAppEnvName = 'ip-geo-analytics-${environment}-env'
var storageMountName = 'pgdatavolume'
var postgresMountOptions = 'uid=70,gid=70,nobrl,mfsymlinks,cache=none,dir_mode=0700,file_mode=0700'
var logAnalyticsWorkspaceName = 'ip-geo-analytics-${environment}-logs'
var appInsightsName = 'ip-geo-analytics-${environment}-appinsights'

// Storage Account for PostgreSQL persistence
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    largeFileSharesState: 'Enabled'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// File Share for PostgreSQL data
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: '${storageAccount.name}/default/${storageShareName}'
  properties: {
    shareQuota: 1024
    enabledProtocols: 'SMB'
  }
}

// Log Analytics Workspace for Application Insights and Container Apps logging
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
  }
}

// Application Insights for monitoring and debugging
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
  }
}

// Container Apps Environment
resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    zoneRedundant: false
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

// Storage mount configuration for Container Apps Environment
resource envStorage 'Microsoft.App/managedEnvironments/storages@2023-05-01' = {
  name: storageMountName
  parent: containerAppEnv
  properties: {
    azureFile: {
      accountName: storageAccount.name
      accountKey: storageAccount.listKeys().keys[0].value
      shareName: storageShareName
      accessMode: 'ReadWrite'
    }
  }
}

// PostgreSQL Container App
// IMPORTANT: minReplicas=1 is strongly recommended for databases to avoid:
// 1. Data consistency issues during cold-start
// 2. Long startup times (30-60s) that cause dependent apps to fail
// 3. Connection timeout cascades that are hard to recover from
// If cost optimization is critical, consider Azure Database for PostgreSQL Flexible Server
// with auto-pause instead of containerized PostgreSQL with scale-to-zero.
resource postgresApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'postgres'
  location: location
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 5432
        transport: 'tcp'
      }
    }
    template: {
      containers: [
        {
          name: 'postgres'
          image: 'postgres:18-alpine'
          env: [
            {
              name: 'POSTGRES_USER'
              value: 'admin'
            }
            {
              name: 'POSTGRES_PASSWORD'
              value: postgresPassword
            }
            {
              name: 'POSTGRES_DB'
              value: 'analytics'
            }
            {
              name: 'PGDATA'
              value: '/var/lib/postgresql/data/pgdata'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          volumeMounts: [
            {
              volumeName: storageMountName
              mountPath: '/var/lib/postgresql/data'
            }
          ]
          // Add liveness probe to ensure PostgreSQL is actually accepting connections
          probes: [
            {
              type: 'Liveness'
              tcpSocket: {
                port: 5432
              }
              initialDelaySeconds: 15
              periodSeconds: 20
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        // Keep PostgreSQL always running - databases should not scale to zero
        // This prevents connection failures and long cold-start delays
        minReplicas: 1
        maxReplicas: 1
      }
      volumes: [
        {
          name: storageMountName
          storageType: 'AzureFile'
          storageName: storageMountName
          mountOptions: postgresMountOptions
        }
      ]
    }
  }
  dependsOn: [
    envStorage
  ]
}

// Application Container App
resource appContainerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'app'
  location: location
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 3000
        transport: 'auto'
      }
      registries: [
        {
          server: registryServer
          username: registryUsername
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: registryPassword
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'app'
          image: imageTag
          env: [
            {
              name: 'NODE_ENV'
              value: 'production'
            }
            {
              name: 'PORT'
              value: '3000'
            }
            {
              name: 'DATABASE_URL'
              value: 'postgresql://admin:${postgresPassword}@postgres:5432/analytics?schema=public'
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          probes: [
            {
              // Startup probe: Very generous timeout for initial startup
              // This handles: container cold-start, npm/node initialization, 
              // and initial database connection with retries
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: 3000
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              timeoutSeconds: 10
              failureThreshold: 18  // Allow up to 3 minutes for startup (18 * 10s)
            }
            {
              // Liveness probe: Checks if app process is healthy
              // Uses /health endpoint which has DB retry logic built-in
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 3000
              }
              initialDelaySeconds: 0  // Starts after startup probe succeeds
              periodSeconds: 30
              timeoutSeconds: 15  // Allow time for DB connection retry
              failureThreshold: 3
            }
            {
              // Readiness probe: Determines if app can serve traffic
              // Uses /ready endpoint with aggressive DB retry to wake up PostgreSQL
              type: 'Readiness'
              httpGet: {
                path: '/ready'
                port: 3000
              }
              initialDelaySeconds: 0  // Starts after startup probe succeeds
              periodSeconds: 15  // Check frequently to recover quickly
              timeoutSeconds: 30  // Allow time for PostgreSQL wake-up retries
              failureThreshold: 2  // Quick to mark not ready, but probe will keep trying
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
      }
    }
  }
  dependsOn: [
    postgresApp
  ]
}

// Outputs
output appUrl string = 'https://${appContainerApp.properties.configuration.ingress.fqdn}'
output storageAccountName string = storageAccount.name
output containerAppEnvName string = containerAppEnv.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
