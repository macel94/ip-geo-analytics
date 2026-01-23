#!/bin/bash
# Load testing script using artillery

set -e

# Configuration
ENDPOINT="${1:-http://localhost:3000}"
DURATION="${DURATION:-300}"
WARM_UP_RATE="${WARM_UP_RATE:-10}"
SUSTAINED_RATE="${SUSTAINED_RATE:-50}"
PEAK_RATE="${PEAK_RATE:-100}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if artillery is installed
if ! command -v artillery &> /dev/null; then
    echo -e "${YELLOW}Artillery not found. Installing...${NC}"
    npm install -g artillery
fi

echo -e "${GREEN}Starting load test for: $ENDPOINT${NC}"
echo -e "${YELLOW}Test duration: ${DURATION}s${NC}"
echo -e "${YELLOW}Warm up rate: ${WARM_UP_RATE} req/sec${NC}"
echo -e "${YELLOW}Sustained rate: ${SUSTAINED_RATE} req/sec${NC}"
echo -e "${YELLOW}Peak rate: ${PEAK_RATE} req/sec${NC}"

# Create test configuration
cat > /tmp/load-test.yml <<EOF
config:
  target: "$ENDPOINT"
  phases:
    - duration: 60
      arrivalRate: $WARM_UP_RATE
      name: "Warm up"
    - duration: 180
      arrivalRate: $SUSTAINED_RATE
      name: "Sustained load"
    - duration: 60
      arrivalRate: $PEAK_RATE
      name: "Peak load"
  processor: "./processor.js"
  
scenarios:
  - name: "Track visitor"
    weight: 70
    flow:
      - post:
          url: "/api/track"
          json:
            site_id: "{{ \$randomString() }}"
            referrer: "https://example.com/{{ \$randomString() }}"
  
  - name: "Get stats"
    weight: 30
    flow:
      - get:
          url: "/api/stats?site_id=test-site"
      
  - name: "Health check"
    weight: 5
    flow:
      - get:
          url: "/health"
EOF

# Create processor file for custom functions
cat > /tmp/processor.js <<'EOF'
module.exports = {
  $randomString: function() {
    return Math.random().toString(36).substring(7);
  }
};
EOF

# Run the test
echo -e "${GREEN}Running load test...${NC}"
artillery run /tmp/load-test.yml --output /tmp/load-test-results.json

# Generate HTML report
echo -e "${GREEN}Generating HTML report...${NC}"
artillery report /tmp/load-test-results.json --output ./load-test-report.html

# Cleanup
rm /tmp/load-test.yml /tmp/processor.js

echo -e "${GREEN}✅ Load test completed!${NC}"
echo -e "${GREEN}Report saved to: ./load-test-report.html${NC}"
