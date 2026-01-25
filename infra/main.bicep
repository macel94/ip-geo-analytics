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
resource containerAppEnv 'Microsoft.App/managedEnvironments@2025-10-02-preview' = {
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
resource envStorage 'Microsoft.App/managedEnvironments/storages@2025-10-02-preview' = {
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
// Configured for scale-to-zero to optimize costs. The app container has retry logic
// to handle cold-start scenarios when PostgreSQL needs to wake up.
// TCP scale rule triggers scale-up when connections are attempted.
resource postgresApp 'Microsoft.App/containerApps@2025-10-02-preview' = {
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
          probes: [
            {
              type: 'Liveness'
              tcpSocket: {
                port: 5432
              }
              initialDelaySeconds: 15
              periodSeconds: 60  // Check every minute instead of every 20 seconds
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
        cooldownPeriod: 600  // 10 minutes cooldown period before scaling down
        pollingInterval: 60  // Check metrics every 60 seconds instead of default 30
        rules: [
          {
            name: 'tcp-scale-rule'
            tcp: {
              metadata: {
                concurrentConnections: '1'  // Scale up on first connection attempt
              }
            }
          }
        ]
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
resource appContainerApp 'Microsoft.App/containerApps@2025-10-02-preview' = {
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
              // and initial database connection with retries (PostgreSQL may need 30-60s to wake)
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: 3000
              }
              initialDelaySeconds: 5
              periodSeconds: 15
              timeoutSeconds: 120  // 2 minutes to allow for DB cold-start retries
              failureThreshold: 12  // Allow up to 3 minutes for startup (12 * 15s)
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
              periodSeconds: 60  // Check every minute
              timeoutSeconds: 120  // 2 minutes to allow PostgreSQL wake-up
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
              periodSeconds: 30  // Check frequently to recover quickly
              timeoutSeconds: 180  // 3 minutes to handle full PostgreSQL cold-start
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
