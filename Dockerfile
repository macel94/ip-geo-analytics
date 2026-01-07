# Stage 1: Build Client (Vite)
FROM node:24-alpine AS client-builder
WORKDIR /app/client
COPY client/package*.json ./
RUN npm ci
COPY client/ .
RUN npm run build

# Stage 2: Build Server (TypeScript)
FROM node:24-alpine AS server-builder
WORKDIR /app/server
COPY server/package*.json ./
RUN npm ci
COPY server/ .
# Generate Prisma Client
RUN npx prisma generate
RUN npm run build

# Stage 3: Production Runtime
FROM node:24-alpine
WORKDIR /app

# Install production dependencies for server
COPY server/package*.json ./
# We need prisma in production to run migrations or use the client
RUN npm ci --omit=dev && npm install -g prisma

# Copy built artifacts
COPY --from=server-builder /app/server/dist ./dist
COPY --from=server-builder /app/server/prisma ./prisma
COPY --from=server-builder /app/server/node_modules/.prisma ./node_modules/.prisma
COPY --from=client-builder /app/client/dist ./client/dist

# Create directory for GeoIP database
RUN mkdir -p /app/geoip

# Environment defaults
ENV NODE_ENV=production
ENV PORT=3000

# Expose port
EXPOSE 3000

# Start command: Apply migrations (if needed) and start server
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/index.js"]
