#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Ensure we are executing from the project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

echo -e "${GREEN}1. Installing dependencies (Root)...${NC}"
npm install

echo -e "${GREEN}2. Installing dependencies (Server)...${NC}"
cd server && npm install && cd ..

echo -e "${GREEN}3. Installing dependencies (Client)...${NC}"
cd client && npm install && cd ..

echo -e "${GREEN}4. Starting Local Database (Docker)...${NC}"
docker-compose up -d

echo -e "${GREEN}5. Waiting for Database to be ready...${NC}"
# Simple wait loop
until docker exec ip-geo-postgres pg_isready -U admin -d analytics; do
  echo "Waiting for Postgres..."
  sleep 2
done

echo -e "${GREEN}6. Setting up Environment Variables (Server)...${NC}"
# Create .env if it doesn't exist
if [ ! -f server/.env ]; then
    echo "DATABASE_URL=\"postgresql://admin:password123@localhost:5432/analytics?schema=public\"" > server/.env
    echo "Created server/.env"
else
    echo "server/.env already exists, skipping."
fi

echo -e "${GREEN}7. Running Database Migrations...${NC}"
cd server
npx prisma db push
cd ..

echo -e "${GREEN}✅ Setup Complete! Run 'npm run dev' or './scripts/start_dev.sh' to start.${NC}"
