// Main deployment template for IP Geo Analytics infrastructure

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (staging or production)')
param environment string = 'staging'

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
// IMPORTANT: PostgreSQL must have minReplicas=1 because:
// 1. It's a stateful workload that needs to be always available
// 2. TCP connections cannot "wake up" a scaled-to-zero container like HTTP can
// 3. The app container depends on PostgreSQL being available on startup
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
          image: 'postgres:15-alpine'
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
            cpu: json('0.25')
            memory: '0.5Gi'
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
              initialDelaySeconds: 30
              periodSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              tcpSocket: {
                port: 5432
              }
              initialDelaySeconds: 10
              periodSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      volumes: [
        {
          name: storageMountName
          storageType: 'AzureFile'
          storageName: storageMountName
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
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: 3000
              }
              initialDelaySeconds: 10
              periodSeconds: 5
              failureThreshold: 30  // Allow up to 2.5 minutes for startup (migrations, cold start)
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 3000
              }
              initialDelaySeconds: 0  // Starts after startup probe succeeds
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/ready'
                port: 3000
              }
              initialDelaySeconds: 0  // Starts after startup probe succeeds
              periodSeconds: 10
              failureThreshold: 3
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
