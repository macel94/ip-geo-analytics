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

// Variables
var storageAccountName = 'ipgeoanalyticssa'
var storageShareName = 'pgdata'
var containerAppEnvName = 'ip-geo-analytics-env'
var storageMountName = 'pgdatavolume'

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

// Container Apps Environment
resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    zoneRedundant: false
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
        }
      ]
      scale: {
        minReplicas: 0
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
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
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
