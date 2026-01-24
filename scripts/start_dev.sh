#!/bin/bash
set -e

# Run concurrently via npx from the root to stream logs from both services
# Pass necessary env vars if needed, though server/.env handles DB
echo "Starting Client (Vite) and Server (Fastify)..."

# Ensure we are executing from the project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

# Ensure Prisma Client is generated (workspaces can skip this during install)
cd server
npx prisma generate --config prisma/prisma.config.ts
cd ..

npx concurrently \
    -n "SERVER,CLIENT" \
    -c "blue,magenta" \
    "cd server && npm run dev" \
    "cd client && npm run dev"
