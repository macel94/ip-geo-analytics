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
# Copy workspace root and all package files
COPY package*.json ./
COPY client/package*.json ./client/
COPY server ./server
# Install dependencies
RUN npm install
# Generate Prisma Client
RUN cd server && npx prisma generate
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

# Create directory for GeoIP database
RUN mkdir -p /app/geoip

# Environment defaults
ENV NODE_ENV=production
ENV PORT=3000

# Expose port
EXPOSE 3000

# Start command: Apply migrations (if needed) and start server
CMD ["sh", "-c", "cd server && npx prisma migrate deploy && node dist/index.js"]
