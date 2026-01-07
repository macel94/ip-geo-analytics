#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure we are executing from the project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

echo -e "${GREEN}Setting up E2E test environment...${NC}"

# 1. Check if database is running
echo -e "${YELLOW}1. Checking database status...${NC}"
if ! docker ps | grep -q ip-geo-postgres; then
    echo "Database not running. Starting it now..."
    docker compose up -d
    
    echo "Waiting for database to be ready..."
    until docker exec ip-geo-postgres pg_isready -U admin -d analytics 2>/dev/null; do
        echo "Waiting for Postgres..."
        sleep 2
    done
    echo -e "${GREEN}✓ Database is ready${NC}"
else
    echo -e "${GREEN}✓ Database is already running${NC}"
fi

# 2. Ensure server .env exists
echo -e "${YELLOW}2. Checking server environment...${NC}"
if [ ! -f server/.env ]; then
    echo "Creating server/.env..."
    echo 'DATABASE_URL="postgresql://admin:password123@localhost:5432/analytics?schema=public"' > server/.env
    echo -e "${GREEN}✓ Created server/.env${NC}"
else
    echo -e "${GREEN}✓ server/.env exists${NC}"
fi

# 3. Ensure Prisma schema is pushed
echo -e "${YELLOW}3. Ensuring database schema is up to date...${NC}"
cd server
npx prisma db push --config prisma/prisma.config.ts --accept-data-loss 2>&1 | grep -v "warn" || true
cd ..
echo -e "${GREEN}✓ Database schema is ready${NC}"

# 4. Install Playwright browsers if needed
echo -e "${YELLOW}4. Checking Playwright browsers...${NC}"
if [ ! -d "$HOME/.cache/ms-playwright" ]; then
    echo "Installing Playwright browsers..."
    npx playwright install chromium
    echo -e "${GREEN}✓ Playwright browsers installed${NC}"
else
    echo -e "${GREEN}✓ Playwright browsers already installed${NC}"
fi

echo ""
echo -e "${GREEN}✅ E2E test environment is ready!${NC}"
echo ""
echo "You can now run tests with:"
echo "  npm run test:e2e          - Run tests in headless mode"
echo "  npm run test:e2e:headed   - Run tests with browser visible"
echo "  npm run test:e2e:ui       - Run tests in UI mode"
