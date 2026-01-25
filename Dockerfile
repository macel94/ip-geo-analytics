# Stage 1: Build Client (Vite)
FROM node:25-alpine AS client-builder
WORKDIR /app
# Copy workspace root and all package files
COPY package*.json ./
COPY client ./client
COPY server/package*.json ./server/
# Install dependencies
RUN npm install
# Build client
RUN npm run build --workspace=client

# Stage 2: Build Server (TypeScript)
FROM node:25-alpine AS server-builder
WORKDIR /app
# Prisma config requires DATABASE_URL (no DB connection needed for generate)
ARG DATABASE_URL=postgresql://admin:analytics123@postgres:5432/analytics?schema=public
ENV DATABASE_URL=$DATABASE_URL
# Copy workspace root and all package files
COPY package*.json ./
COPY client/package*.json ./client/
COPY server ./server
# Install dependencies
RUN npm install
# Generate Prisma Client
RUN cd server && npx prisma generate --config prisma/prisma.config.ts
# Build server
RUN npm run build --workspace=server

# Stage 3: Production Runtime
FROM node:25-alpine
WORKDIR /app

# Copy workspace structure with package files
COPY package*.json ./
COPY client/package*.json ./client/
COPY server/package*.json ./server/
# Install production dependencies for server workspace
RUN npm install --omit=dev --workspace=server
# Install prisma CLI separately (needed for migrations)
RUN cd server && npm install prisma

# Copy built artifacts
COPY --from=server-builder /app/server/dist ./server/dist
COPY --from=server-builder /app/server/prisma ./server/prisma
COPY --from=server-builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=client-builder /app/client/dist ./client/dist

# Create directory for GeoIP database and download MMDB
RUN apk add --no-cache curl \
	&& mkdir -p /app/geoip \
	&& curl -L -o /app/geoip/GeoLite2-City.mmdb https://github.com/P3TERX/GeoLite.mmdb/releases/download/2026.01.22/GeoLite2-City.mmdb

# Environment defaults
ENV NODE_ENV=production
ENV PORT=3000

# Expose port
EXPOSE 3000

# Start command: Apply schema (create tables if needed) and start server
# Using db push for simplicity - it creates tables if they don't exist
CMD ["sh", "-c", "cd server && npx prisma db push --config prisma/prisma.config.ts && node dist/index.js"]
