# SRE Runbook - Visitor Analytics

## Overview
This runbook provides operational procedures for the Visitor Analytics application.

## Architecture
- **Frontend**: React + Vite (SPA)
- **Backend**: Fastify (Node.js)
- **Database**: PostgreSQL
- **Deployment**: Azure Container Apps / Kubernetes
- **Monitoring**: Prometheus metrics, Azure Application Insights

## Health Checks

### Health Endpoint
```bash
curl https://your-app.azurecontainerapps.io/health
```

Expected response:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "database": "connected"
}
```

### Readiness Endpoint
```bash
curl https://your-app.azurecontainerapps.io/ready
```

### Metrics Endpoint
```bash
curl https://your-app.azurecontainerapps.io/metrics
```

## Common Operations

### Viewing Logs

#### Azure Container Apps
```bash
# Stream logs
az containerapp logs show \
  --name <app-name> \
  --resource-group rg-visitor-analytics \
  --follow

# Query logs with filters
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "ContainerAppConsoleLogs_CL | where TimeGenerated > ago(1h)"
```

#### Kubernetes
```bash
# View pod logs
kubectl logs -f deployment/visitor-analytics -n visitor-analytics

# View logs from specific pod
kubectl logs -f <pod-name> -n visitor-analytics

# View logs from all pods
kubectl logs -l app=visitor-analytics -n visitor-analytics --all-containers
```

### Scaling

#### Azure Container Apps
```bash
# Manual scaling
az containerapp update \
  --name <app-name> \
  --resource-group rg-visitor-analytics \
  --min-replicas 2 \
  --max-replicas 10
```

#### Kubernetes
```bash
# Manual scaling
kubectl scale deployment visitor-analytics -n visitor-analytics --replicas=5

# Check HPA status
kubectl get hpa -n visitor-analytics
```

### Database Operations

#### Backup
```bash
# Azure PostgreSQL
az postgres flexible-server backup create \
  --name <backup-name> \
  --resource-group rg-visitor-analytics \
  --server-name <server-name>

# Manual backup (Kubernetes)
kubectl exec -n visitor-analytics postgres-0 -- \
  pg_dump -U admin analytics > backup-$(date +%Y%m%d).sql
```

#### Restore
```bash
# Azure PostgreSQL
az postgres flexible-server restore \
  --resource-group rg-visitor-analytics \
  --name <new-server-name> \
  --source-server <source-server> \
  --restore-time "2024-01-01T00:00:00Z"

# Manual restore (Kubernetes)
kubectl exec -i -n visitor-analytics postgres-0 -- \
  psql -U admin analytics < backup-20240101.sql
```

#### Run Migrations
```bash
# Local
cd server && npx prisma migrate deploy

# Container Apps
az containerapp exec \
  --name <app-name> \
  --resource-group rg-visitor-analytics \
  --command "npx prisma migrate deploy"

# Kubernetes
kubectl exec -it deployment/visitor-analytics -n visitor-analytics -- \
  npx prisma migrate deploy
```

### Rollback Deployment

#### Azure Container Apps
```bash
# List revisions
az containerapp revision list \
  --name <app-name> \
  --resource-group rg-visitor-analytics

# Activate previous revision
az containerapp revision activate \
  --name <app-name> \
  --resource-group rg-visitor-analytics \
  --revision <revision-name>
```

#### Kubernetes
```bash
# Rollback to previous version
kubectl rollout undo deployment/visitor-analytics -n visitor-analytics

# Rollback to specific revision
kubectl rollout undo deployment/visitor-analytics -n visitor-analytics --to-revision=2

# Check rollout status
kubectl rollout status deployment/visitor-analytics -n visitor-analytics
```

## Monitoring & Alerting

### Key Metrics to Monitor
1. **Application Metrics**
   - Request rate (`http_requests_total`)
   - Error rate (`http_errors_total`)
   - Response time (p50, p95, p99)
   - Memory usage (`nodejs_memory_usage_bytes`)
   - Uptime (`process_uptime_seconds`)

2. **Database Metrics**
   - Connection pool utilization
   - Query performance
   - Storage usage
   - Replication lag (if applicable)

3. **Infrastructure Metrics**
   - CPU utilization
   - Memory utilization
   - Network throughput
   - Disk I/O

### Setting Up Alerts

#### Azure Monitor
```bash
# Create metric alert for high error rate
az monitor metrics alert create \
  --name "high-error-rate" \
  --resource-group rg-visitor-analytics \
  --scopes <app-resource-id> \
  --condition "avg errors > 10" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action <action-group-id>
```

## Troubleshooting

### High Memory Usage
1. Check metrics endpoint for memory stats
2. Review application logs for memory leaks
3. Check database connection pool size
4. Consider increasing container memory limits

### Database Connection Issues
1. Verify DATABASE_URL environment variable
2. Check database health:
   ```bash
   kubectl exec -n visitor-analytics postgres-0 -- pg_isready
   ```
3. Review connection pool settings
4. Check network policies and firewall rules

### Slow Response Times
1. Check database query performance:
   ```sql
   SELECT * FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;
   ```
2. Review Fastify logs for slow routes
3. Check if GeoIP database is accessible
4. Verify external service dependencies

### Application Won't Start
1. Check environment variables are set correctly
2. Verify database is accessible
3. Check if migrations have been applied
4. Review application logs for errors

## Incident Response

### Severity Levels
- **P0 (Critical)**: Service is down, data loss risk
- **P1 (High)**: Major functionality impaired
- **P2 (Medium)**: Partial functionality impaired
- **P3 (Low)**: Minor issues, cosmetic problems

### Response Procedure
1. **Acknowledge**: Confirm you're investigating
2. **Assess**: Determine severity and impact
3. **Mitigate**: Take immediate action to restore service
4. **Communicate**: Update stakeholders regularly
5. **Resolve**: Fix root cause
6. **Document**: Write postmortem

## Disaster Recovery

### RTO/RPO
- **RTO (Recovery Time Objective)**: 4 hours
- **RPO (Recovery Point Objective)**: 1 hour

### DR Procedure
1. Verify nature of disaster
2. Activate incident response team
3. Restore from most recent backup
4. Verify data integrity
5. Update DNS/routing if needed
6. Monitor system stability
7. Conduct postmortem

## Security

### Secret Management
- Use Azure Key Vault or Kubernetes Secrets
- Rotate credentials quarterly
- Never commit secrets to git

### Access Control
- Use RBAC for Azure resources
- Use Kubernetes RBAC for cluster access
- Enable MFA for all admin accounts
- Review access logs regularly

### Vulnerability Management
- Automated scanning via GitHub Actions
- Weekly dependency updates via Dependabot
- Monthly security review
- Immediate patching for critical CVEs

## Contacts

### On-Call Schedule
- Primary: [On-call rotation]
- Secondary: [Backup on-call]
- Escalation: [Team lead]

### Communication Channels
- Incidents: [Slack/Teams channel]
- Status Page: [URL]
- Documentation: [Wiki URL]
