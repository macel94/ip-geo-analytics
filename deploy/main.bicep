param location string = resourceGroup().location
param appName string = 'visitor-analytics-${uniqueString(resourceGroup().id)}'
param dbPassword string {
  secure: true
}

// 1. Container Registry (Optional, assuming you push to ACR or DockerHub)
// For simplicity, we assume image handles allow public or you configure ACR auth separately.

// 2. Azure Database for PostgreSQL (Flexible Server)
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2022-12-01' = {
  name: '${appName}-db'
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '14'
    administratorLogin: 'adminuser'
    administratorLoginPassword: dbPassword
    storage: {
      storageSizeGB: 32
    }
  }
}

// Allow access from Azure Services
resource firewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2022-12-01' = {
  parent: postgresServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2022-12-01' = {
  parent: postgresServer
  name: 'analytics'
}

// 3. Container App Environment
resource env 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: '${appName}-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'azure-monitor'
    }
  }
}

// 4. Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: '${appName}-app'
  location: location
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      ingress: {
        external: true
        targetPort: 3000
        transport: 'auto'
      }
      secrets: [
        {
          name: 'db-password'
          value: dbPassword
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'main'
          image: 'ghcr.io/macel94/ip-geo-analytics:latest' // Replace with your actual image
          env: [
            {
              name: 'DATABASE_URL'
              value: 'postgresql://adminuser:${dbPassword}@${postgresServer.properties.fullyQualifiedDomainName}:5432/analytics'
            }
            // If you mount GeoIP via storage volume, you'd configure volumeMounts here
          ]
          resources: {
            cpu: 0.5
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}
