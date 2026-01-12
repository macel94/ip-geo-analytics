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

// 3. Log Analytics Workspace for monitoring
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${appName}-logs'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// 4. Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${appName}-insights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// 5. Container App Environment
resource env 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: '${appName}-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// 6. Container App
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
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
            {
              name: 'NODE_ENV'
              value: 'production'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 3000
              }
              initialDelaySeconds: 30
              periodSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/ready'
                port: 3000
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
        maxReplicas: 5
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

// 7. Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${appName}-alerts'
  location: 'global'
  properties: {
    groupShortName: 'VA-Alerts'
    enabled: true
    emailReceivers: [
      // Add your email here
      // {
      //   name: 'Admin'
      //   emailAddress: 'admin@example.com'
      //   useCommonAlertSchema: true
      // }
    ]
  }
}

// 8. Metric Alerts
resource highErrorRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${appName}-high-error-rate'
  location: 'global'
  properties: {
    description: 'Alert when error rate is high'
    severity: 2
    enabled: true
    scopes: [
      containerApp.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Metric1'
          metricName: 'Requests'
          dimensions: [
            {
              name: 'statusCode'
              operator: 'Include'
              values: ['5*']
            }
          ]
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Total'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

resource highMemoryAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${appName}-high-memory'
  location: 'global'
  properties: {
    description: 'Alert when memory usage is high'
    severity: 3
    enabled: true
    scopes: [
      containerApp.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Metric1'
          metricName: 'WorkingSetBytes'
          operator: 'GreaterThan'
          threshold: 900000000 // 900MB
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Outputs
output appUrl string = containerApp.properties.configuration.ingress.fqdn
output logAnalyticsWorkspaceId string = logAnalytics.id
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString
