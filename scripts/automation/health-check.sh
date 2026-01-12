#!/bin/bash
# Health check monitoring script with alerting

set -e

# Configuration
ENDPOINT="${HEALTH_ENDPOINT:-http://localhost:3000/health}"
METRICS_ENDPOINT="${METRICS_ENDPOINT:-http://localhost:3000/metrics}"
SLACK_WEBHOOK="${SLACK_WEBHOOK_URL}"
ALERT_EMAIL="${ALERT_EMAIL}"
MAX_RETRIES=3
RETRY_DELAY=5

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

check_health() {
    local endpoint="$1"
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        local response=$(curl -s -o /tmp/health_response.json -w "%{http_code}" "$endpoint" 2>/dev/null || echo "000")
        
        if [ "$response" = "200" ]; then
            local status=$(cat /tmp/health_response.json | jq -r '.status' 2>/dev/null || echo "unknown")
            if [ "$status" = "healthy" ]; then
                echo -e "${GREEN}✅ Health check passed${NC}"
                return 0
            fi
        fi
        
        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
            echo -e "${YELLOW}⚠️  Retry $retries/$MAX_RETRIES after ${RETRY_DELAY}s...${NC}"
            sleep $RETRY_DELAY
        fi
    done
    
    echo -e "${RED}❌ Health check failed after $MAX_RETRIES attempts (Status: $response)${NC}"
    return 1
}

check_metrics() {
    local endpoint="$1"
    local response=$(curl -s "$endpoint" 2>/dev/null)
    
    if [ -z "$response" ]; then
        echo -e "${YELLOW}⚠️  Could not fetch metrics${NC}"
        return 1
    fi
    
    # Extract key metrics
    local uptime=$(echo "$response" | grep "process_uptime_seconds" | grep -v "#" | awk '{print $2}')
    local requests=$(echo "$response" | grep "http_requests_total" | grep -v "#" | awk '{print $2}')
    local errors=$(echo "$response" | grep "http_errors_total" | grep -v "#" | awk '{print $2}')
    
    echo -e "${GREEN}📊 Metrics:${NC}"
    echo -e "  Uptime: ${uptime}s"
    echo -e "  Total Requests: ${requests}"
    echo -e "  Total Errors: ${errors}"
    
    # Calculate error rate
    if [ -n "$requests" ] && [ -n "$errors" ] && [ "$requests" != "0" ]; then
        local error_rate=$(echo "scale=4; $errors / $requests * 100" | bc)
        echo -e "  Error Rate: ${error_rate}%"
        
        # Alert if error rate is high
        local threshold=5
        if (( $(echo "$error_rate > $threshold" | bc -l) )); then
            echo -e "${RED}⚠️  High error rate detected: ${error_rate}%${NC}"
            send_alert "High error rate detected: ${error_rate}% (threshold: ${threshold}%)"
        fi
    fi
}

send_alert() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local full_message="[$timestamp] $message"
    
    echo -e "${YELLOW}Sending alert: $message${NC}"
    
    # Send to Slack
    if [ -n "$SLACK_WEBHOOK" ]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🚨 Alert: $full_message\"}" \
            "$SLACK_WEBHOOK" > /dev/null
        echo -e "${GREEN}Alert sent to Slack${NC}"
    fi
    
    # Send email
    if [ -n "$ALERT_EMAIL" ] && command -v mail &> /dev/null; then
        echo "$full_message" | mail -s "🚨 Visitor Analytics Alert" "$ALERT_EMAIL"
        echo -e "${GREEN}Alert sent to email${NC}"
    fi
    
    # Log to file
    echo "$full_message" >> /var/log/health-check-alerts.log 2>/dev/null || true
}

# Main execution
echo "==================================="
echo "Visitor Analytics Health Check"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "==================================="

if check_health "$ENDPOINT"; then
    check_metrics "$METRICS_ENDPOINT"
    exit 0
else
    send_alert "Health check failed for $ENDPOINT"
    exit 1
fi
