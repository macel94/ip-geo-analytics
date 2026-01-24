# Automation Scripts

This directory contains automation scripts for SRE operations.

## Database Backup

### Automated Backup Script

```bash
#!/bin/bash
# scripts/backup-database.sh

set -e

BACKUP_DIR="${BACKUP_DIR:-/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/analytics_backup_$TIMESTAMP.sql"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Perform backup
pg_dump "$DATABASE_URL" > "$BACKUP_FILE"

# Compress backup
gzip "$BACKUP_FILE"

# Upload to cloud storage (example with Azure)
if [ -n "$AZURE_STORAGE_ACCOUNT" ]; then
    az storage blob upload \
        --account-name "$AZURE_STORAGE_ACCOUNT" \
        --container-name backups \
        --name "analytics_backup_$TIMESTAMP.sql.gz" \
        --file "$BACKUP_FILE.gz"
fi

# Cleanup old backups (keep last 7 days)
find "$BACKUP_DIR" -name "analytics_backup_*.sql.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE.gz"
```

### Cron Job Setup

```bash
# Add to crontab (daily at 2 AM)
0 2 * * * /app/scripts/backup-database.sh >> /var/log/backup.log 2>&1
```

### Kubernetes CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: database-backup
  namespace: visitor-analytics
spec:
  schedule: "0 2 * * *" # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: postgres:18-alpine
              env:
                - name: DATABASE_URL
                  valueFrom:
                    secretKeyRef:
                      name: db-credentials
                      key: DATABASE_URL
              command:
                - /bin/sh
                - -c
                - |
                  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                  pg_dump "$DATABASE_URL" | gzip > /backups/backup_$TIMESTAMP.sql.gz
              volumeMounts:
                - name: backup-storage
                  mountPath: /backups
          volumes:
            - name: backup-storage
              persistentVolumeClaim:
                claimName: backup-pvc
          restartPolicy: OnFailure
```

## Health Check Monitoring

### Simple Uptime Monitor

```bash
#!/bin/bash
# scripts/health-check.sh

ENDPOINT="${HEALTH_ENDPOINT:-http://localhost:3000/health}"
SLACK_WEBHOOK="${SLACK_WEBHOOK_URL}"

check_health() {
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$ENDPOINT")

    if [ "$response" != "200" ]; then
        echo "Health check failed with status: $response"
        send_alert "Health check failed for $ENDPOINT (Status: $response)"
        return 1
    fi

    echo "Health check passed"
    return 0
}

send_alert() {
    local message="$1"

    if [ -n "$SLACK_WEBHOOK" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"⚠️ Alert: $message\"}" \
            "$SLACK_WEBHOOK"
    fi

    # Send email (if configured)
    if [ -n "$ALERT_EMAIL" ]; then
        echo "$message" | mail -s "Health Check Alert" "$ALERT_EMAIL"
    fi
}

check_health
```

## Performance Testing

### Load Testing Script

```bash
#!/bin/bash
# scripts/load-test.sh

# Requirements: artillery (npm install -g artillery)

ENDPOINT="${1:-http://localhost:3000}"

cat > /tmp/load-test.yml <<EOF
config:
  target: "$ENDPOINT"
  phases:
    - duration: 60
      arrivalRate: 10
      name: "Warm up"
    - duration: 120
      arrivalRate: 50
      name: "Sustained load"
    - duration: 60
      arrivalRate: 100
      name: "Peak load"

scenarios:
  - name: "Track visitor"
    flow:
      - post:
          url: "/api/track"
          json:
            site_id: "test-site"
            referrer: "https://example.com"

  - name: "Get stats"
    flow:
      - get:
          url: "/api/stats?site_id=test-site"
EOF

artillery run /tmp/load-test.yml

rm /tmp/load-test.yml
```

## Deployment Automation

### Blue-Green Deployment Script

```bash
#!/bin/bash
# scripts/blue-green-deploy.sh

set -e

NAMESPACE="${NAMESPACE:-visitor-analytics}"
NEW_VERSION="${1:?Version required}"

echo "Starting blue-green deployment for version $NEW_VERSION"

# Deploy new version (green)
kubectl set image deployment/visitor-analytics \
    app=ghcr.io/macel94/ip-geo-analytics:$NEW_VERSION \
    -n $NAMESPACE

# Wait for rollout
kubectl rollout status deployment/visitor-analytics -n $NAMESPACE --timeout=5m

# Run smoke tests
echo "Running smoke tests..."
ENDPOINT=$(kubectl get svc visitor-analytics -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
HEALTH_CHECK=$(curl -s http://$ENDPOINT/health | jq -r '.status')

if [ "$HEALTH_CHECK" != "healthy" ]; then
    echo "Health check failed, rolling back..."
    kubectl rollout undo deployment/visitor-analytics -n $NAMESPACE
    exit 1
fi

echo "Deployment successful!"
```

### Canary Deployment (with Istio)

```yaml
# scripts/canary-deploy.yaml
apiVersion: v1
kind: Service
metadata:
  name: visitor-analytics-canary
  namespace: visitor-analytics
spec:
  selector:
    app: visitor-analytics
    version: canary
  ports:
    - port: 80
      targetPort: 3000
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: visitor-analytics
  namespace: visitor-analytics
spec:
  hosts:
    - visitor-analytics
  http:
    - match:
        - headers:
            canary:
              exact: "true"
      route:
        - destination:
            host: visitor-analytics-canary
    - route:
        - destination:
            host: visitor-analytics
          weight: 90
        - destination:
            host: visitor-analytics-canary
          weight: 10
```

## Log Aggregation

### Fluentd Configuration

```yaml
# scripts/fluentd-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
  namespace: visitor-analytics
data:
  fluent.conf: |
    <source>
      @type tail
      path /var/log/containers/visitor-analytics*.log
      pos_file /var/log/fluentd-visitor-analytics.pos
      tag kubernetes.*
      <parse>
        @type json
        time_format %Y-%m-%dT%H:%M:%S.%NZ
      </parse>
    </source>

    <filter kubernetes.**>
      @type kubernetes_metadata
    </filter>

    <match kubernetes.**>
      @type elasticsearch
      host elasticsearch-service
      port 9200
      logstash_format true
      logstash_prefix visitor-analytics
    </match>
```

## Chaos Engineering

### Chaos Mesh Experiments

```yaml
# scripts/chaos-experiments.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-failure
  namespace: visitor-analytics
spec:
  action: pod-failure
  mode: one
  duration: "30s"
  selector:
    namespaces:
      - visitor-analytics
    labelSelectors:
      app: visitor-analytics
  scheduler:
    cron: "@every 1h"
---
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-delay
  namespace: visitor-analytics
spec:
  action: delay
  mode: all
  selector:
    namespaces:
      - visitor-analytics
    labelSelectors:
      app: visitor-analytics
  delay:
    latency: "100ms"
    jitter: "50ms"
  duration: "1m"
  scheduler:
    cron: "@every 2h"
```

## Alerting Rules

### Prometheus Alert Rules

```yaml
# scripts/prometheus-alerts.yaml
groups:
  - name: visitor-analytics
    interval: 30s
    rules:
      - alert: HighErrorRate
        expr: rate(http_errors_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value }} requests/second"

      - alert: HighMemoryUsage
        expr: nodejs_memory_usage_bytes{type="heapUsed"} / nodejs_memory_usage_bytes{type="heapTotal"} > 0.9
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage"
          description: "Memory usage is above 90%"

      - alert: ServiceDown
        expr: up{job="visitor-analytics"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Service is down"
          description: "Visitor Analytics service is not responding"

      - alert: DatabaseConnectionFailure
        expr: increase(http_errors_total[5m]) > 100
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Possible database connection issues"
          description: "High number of errors may indicate database problems"
```

## Usage

### Setting up automated backups

```bash
# Azure Container Apps
az containerapp job create \
  --name backup-job \
  --resource-group rg-visitor-analytics \
  --environment <env-name> \
  --trigger-type "Schedule" \
  --cron-expression "0 2 * * *" \
  --image postgres:18-alpine \
  --command "/bin/sh" \
  --args "-c" "pg_dump \$DATABASE_URL | gzip > /backups/backup_\$(date +%Y%m%d).sql.gz"
```

### Running performance tests

```bash
# Install artillery
npm install -g artillery

# Run load test
./scripts/load-test.sh https://your-app.azurecontainerapps.io
```

### Deploying with canary strategy

```bash
# Apply canary configuration
kubectl apply -f scripts/canary-deploy.yaml

# Monitor canary metrics
kubectl logs -f deployment/visitor-analytics-canary -n visitor-analytics

# Promote canary if successful
kubectl scale deployment/visitor-analytics-canary --replicas=0 -n visitor-analytics
kubectl set image deployment/visitor-analytics app=<new-image> -n visitor-analytics
```
