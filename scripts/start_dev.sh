#!/bin/bash
set -e

# Run concurrently via npx from the root to stream logs from both services
# Pass necessary env vars if needed, though server/.env handles DB
echo "Starting Client (Vite) and Server (Fastify)..."

npx concurrently \
    -n "SERVER,CLIENT" \
    -c "blue,magenta" \
    "cd server && npm run dev" \
    "cd client && npm run dev"
