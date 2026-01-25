import "dotenv/config";
import Fastify, { FastifyRequest } from "fastify";
import path from "path";
import fastifyStatic from "@fastify/static";
import fastifyCors from "@fastify/cors";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import pg from "pg";
import { initGeoIp, getGeoData } from "./services/geoip";
import { UAParser } from "ua-parser-js";

const fastify = Fastify({
  logger: true,
  trustProxy: true, // CRITICAL: for Azure Load Balancer / Ingress
});

const PORT = Number(process.env.PORT) || 3000;
const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl) {
  throw new Error("DATABASE_URL is required to start the server.");
}

// Setup PostgreSQL connection pool for Prisma adapter
// Configure pool with retry-friendly settings for cold-start scenarios
const pool = new pg.Pool({
  connectionString: databaseUrl,
  connectionTimeoutMillis: 30000, // 30s timeout for initial connection (cold start)
  idleTimeoutMillis: 30000,
  max: 10,
});

// Log pool errors but don't crash - allows retry logic to work
pool.on("error", (err) => {
  fastify.log.error({ err }, "PostgreSQL pool error");
});

const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter });

// Database connection state tracking
let dbConnected = false;
let lastDbCheck = 0;
const DB_CHECK_INTERVAL = 5000; // 5 seconds between checks

/**
 * Retry a database operation with exponential backoff.
 * This is critical for Azure Container Apps where PostgreSQL may scale to zero
 * and need time to wake up when the app starts or receives traffic.
 */
async function withDbRetry<T>(
  operation: () => Promise<T>,
  options: {
    maxRetries?: number;
    initialDelayMs?: number;
    maxDelayMs?: number;
    operationName?: string;
  } = {},
): Promise<T> {
  const {
    maxRetries = 5,
    initialDelayMs = 1000,
    maxDelayMs = 30000,
    operationName = "database operation",
  } = options;

  let lastError: Error | null = null;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const result = await operation();
      if (!dbConnected) {
        dbConnected = true;
        fastify.log.info("Database connection established");
      }
      return result;
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      dbConnected = false;

      // Check if it's a connection error that's worth retrying
      const isRetryable =
        lastError.message.includes("ECONNREFUSED") ||
        lastError.message.includes("connection") ||
        lastError.message.includes("timeout") ||
        lastError.message.includes("ETIMEDOUT") ||
        lastError.message.includes("Can't reach database");

      if (attempt < maxRetries && isRetryable) {
        const delay = Math.min(
          initialDelayMs * Math.pow(2, attempt - 1),
          maxDelayMs,
        );
        fastify.log.warn(
          `${operationName} failed (attempt ${attempt}/${maxRetries}), retrying in ${delay}ms: ${lastError.message}`,
        );
        await new Promise((resolve) => setTimeout(resolve, delay));
      } else if (!isRetryable) {
        // Non-retryable error, throw immediately
        throw lastError;
      }
    }
  }

  throw lastError;
}

/**
 * Check database connectivity with caching to avoid hammering the DB
 */
async function checkDbConnection(): Promise<boolean> {
  const now = Date.now();
  if (dbConnected && now - lastDbCheck < DB_CHECK_INTERVAL) {
    return true;
  }

  try {
    await prisma.$queryRaw`SELECT 1`;
    dbConnected = true;
    lastDbCheck = now;
    return true;
  } catch {
    dbConnected = false;
    return false;
  }
}

// Initialize services
initGeoIp();

fastify.register(fastifyCors, {
  origin: "*", // Lock this down in production
});

// Serve frontend static files
fastify.register(fastifyStatic, {
  root: path.join(__dirname, "../../client/dist"),
  prefix: "/",
});

interface TrackBody {
  site_id?: string;
  referrer?: string;
}

interface TrackQuery {
  site_id?: string;
  referrer?: string;
}

// Health Check Endpoint - for load balancers and monitoring
// This endpoint uses retry logic to handle PostgreSQL cold-start scenarios
fastify.get("/health", async (request, reply) => {
  try {
    // Use retry logic to allow PostgreSQL to wake up from scale-to-zero
    // PostgreSQL cold-start can take 30-60s, so we retry for up to ~90s
    await withDbRetry(() => prisma.$queryRaw`SELECT 1`, {
      maxRetries: 10,
      initialDelayMs: 3000,
      maxDelayMs: 15000,
      operationName: "health check",
    });
    return {
      status: "healthy",
      timestamp: new Date().toISOString(),
      database: "connected",
    };
  } catch (error) {
    reply.code(503);
    return {
      status: "unhealthy",
      timestamp: new Date().toISOString(),
      database: "disconnected",
      error: error instanceof Error ? error.message : "Unknown error",
    };
  }
});

// Readiness Check - for Kubernetes/Container Apps
// Uses aggressive retry to wake up PostgreSQL and keep connections active
fastify.get("/ready", async (request, reply) => {
  try {
    // Very aggressive retry for readiness - this keeps trying to wake up PostgreSQL
    // Total retry time: ~2 minutes to handle cold-start scenarios
    await withDbRetry(() => prisma.$queryRaw`SELECT 1`, {
      maxRetries: 12,
      initialDelayMs: 5000,
      maxDelayMs: 15000,
      operationName: "readiness check",
    });
    return { status: "ready" };
  } catch (error) {
    reply.code(503);
    return {
      status: "not ready",
      reason: error instanceof Error ? error.message : "Database unavailable",
    };
  }
});

// Debug Endpoint - check what IP is being detected and GeoIP result
fastify.get("/api/debug/ip", async (request, reply) => {
  const ip = request.ip;
  const xForwardedFor = request.headers["x-forwarded-for"];
  const xRealIp = request.headers["x-real-ip"];
  const geo = getGeoData(ip);

  return {
    resolvedIp: ip,
    xForwardedFor,
    xRealIp,
    remoteAddress: request.socket?.remoteAddress,
    geoData: geo,
    note:
      ip === "127.0.0.1" ||
      ip === "::1" ||
      ip?.startsWith("10.") ||
      ip?.startsWith("172.") ||
      ip?.startsWith("192.168.")
        ? "Private/local IP detected - GeoIP lookup will not work for private IPs"
        : "Public IP detected",
  };
});

// Metrics Endpoint - basic Prometheus-style metrics
let requestCount = 0;
let trackingCount = 0;
let errorCount = 0;
const startTime = Date.now();

fastify.addHook("onRequest", async (request, reply) => {
  requestCount++;
});

fastify.get("/metrics", async (request, reply) => {
  const uptime = (Date.now() - startTime) / 1000;
  const metrics = [
    `# HELP http_requests_total Total number of HTTP requests`,
    `# TYPE http_requests_total counter`,
    `http_requests_total ${requestCount}`,
    ``,
    `# HELP tracking_requests_total Total number of tracking requests`,
    `# TYPE tracking_requests_total counter`,
    `tracking_requests_total ${trackingCount}`,
    ``,
    `# HELP http_errors_total Total number of HTTP errors`,
    `# TYPE http_errors_total counter`,
    `http_errors_total ${errorCount}`,
    ``,
    `# HELP process_uptime_seconds Process uptime in seconds`,
    `# TYPE process_uptime_seconds gauge`,
    `process_uptime_seconds ${uptime}`,
    ``,
    `# HELP nodejs_memory_usage_bytes Node.js memory usage in bytes`,
    `# TYPE nodejs_memory_usage_bytes gauge`,
    `nodejs_memory_usage_bytes{type="rss"} ${process.memoryUsage().rss}`,
    `nodejs_memory_usage_bytes{type="heapTotal"} ${process.memoryUsage().heapTotal}`,
    `nodejs_memory_usage_bytes{type="heapUsed"} ${process.memoryUsage().heapUsed}`,
    `nodejs_memory_usage_bytes{type="external"} ${process.memoryUsage().external}`,
  ].join("\n");

  reply.type("text/plain").send(metrics);
});

// 1. Tracking Endpoint
const trackVisit = async (
  request: FastifyRequest,
  site_id: string,
  referrer?: string,
) => {
  const userAgentString = request.headers["user-agent"] || "";

  // IP Extraction Logic
  // Fastify with trustProxy: true handles X-Forwarded-For automatically via request.ip
  const ip = request.ip;

  // Debug logging for IP troubleshooting
  const xForwardedFor = request.headers["x-forwarded-for"];
  const xRealIp = request.headers["x-real-ip"];
  request.log.info(
    {
      resolvedIp: ip,
      xForwardedFor,
      xRealIp,
      remoteAddress: request.socket?.remoteAddress,
    },
    "IP resolution debug info",
  );

  // GeoIP Lookup
  const geo = getGeoData(ip) || {
    city: null,
    country: null,
    countryCode: null,
  };

  request.log.info({ ip, geo }, "GeoIP lookup result");

  // UA Parsing
  const ua = new UAParser(userAgentString);
  const browser = ua.getBrowser();
  const os = ua.getOS();
  const device = ua.getDevice();

  await prisma.visit.create({
    data: {
      site_id,
      ip_address: ip,
      city: geo.city,
      country: geo.country,
      countryCode: geo.countryCode,
      // asn: ... (requires ASN DB),
      browser: browser.name,
      os: os.name,
      device: device.type || "desktop",
      referrer: referrer || request.headers.referer,
      user_agent: userAgentString,
    },
  });
  trackingCount++;
};

const resolveSiteId = (
  request: FastifyRequest,
  explicitSiteId?: string,
  explicitReferrer?: string,
) => {
  if (explicitSiteId) {
    return explicitSiteId;
  }

  const headerReferrerRaw =
    explicitReferrer || request.headers.referer || request.headers.referrer;
  const headerReferrer = Array.isArray(headerReferrerRaw)
    ? headerReferrerRaw[0]
    : headerReferrerRaw;

  if (headerReferrer) {
    try {
      const url = new URL(headerReferrer);
      if (url.hostname) {
        return url.hostname;
      }
    } catch {
      // ignore invalid referrer
    }
  }

  const host = request.headers.host;
  if (host) {
    return host.split(":")[0];
  }

  return undefined;
};

fastify.post<{ Body: TrackBody }>("/api/track", async (request, reply) => {
  const { site_id, referrer } = request.body;
  const resolvedSiteId = resolveSiteId(request, site_id, referrer);

  if (!resolvedSiteId) {
    reply.code(400).send({ error: "site_id is required" });
    return;
  }

  try {
    // Use retry logic to handle PostgreSQL cold-start (can take 30-60s)
    await withDbRetry(() => trackVisit(request, resolvedSiteId, referrer), {
      maxRetries: 8,
      initialDelayMs: 3000,
      maxDelayMs: 15000,
      operationName: "track visit",
    });
    return { success: true };
  } catch (e) {
    request.log.error(e);
    errorCount++;
    // Return 503 for database connectivity issues to signal temporary unavailability
    const isDbError =
      e instanceof Error &&
      (e.message.includes("connection") || e.message.includes("ECONNREFUSED"));
    reply.code(isDbError ? 503 : 500).send({
      error: isDbError
        ? "Service temporarily unavailable, please retry"
        : "Tracking failed",
    });
  }
});

fastify.get("/api/track", async (request, reply) => {
  const { site_id, referrer } = request.query as TrackQuery;
  const resolvedSiteId = resolveSiteId(request, site_id, referrer);

  if (!resolvedSiteId) {
    reply.code(400).send({ error: "site_id is required" });
    return;
  }

  try {
    // Use retry logic to handle PostgreSQL cold-start (can take 30-60s)
    await withDbRetry(() => trackVisit(request, resolvedSiteId, referrer), {
      maxRetries: 8,
      initialDelayMs: 3000,
      maxDelayMs: 15000,
      operationName: "track visit",
    });
    reply
      .header(
        "Cache-Control",
        "no-store, no-cache, must-revalidate, proxy-revalidate",
      )
      .header("Pragma", "no-cache")
      .header("Expires", "0")
      .send({ success: true });
  } catch (e) {
    request.log.error(e);
    errorCount++;
    const isDbError =
      e instanceof Error &&
      (e.message.includes("connection") || e.message.includes("ECONNREFUSED"));
    reply.code(isDbError ? 503 : 500).send({
      error: isDbError
        ? "Service temporarily unavailable, please retry"
        : "Tracking failed",
    });
  }
});

// Analytics Dashboard Endpoints
fastify.get("/api/stats", async (request, reply) => {
  const { site_id } = request.query as { site_id?: string };
  const where = site_id ? { site_id } : {};

  try {
    // Use retry logic to handle PostgreSQL cold-start
    const [totalVisits, visitsByCountry, mapData] = await withDbRetry(
      () =>
        Promise.all([
          prisma.visit.count({ where }),
          prisma.visit.groupBy({
            by: ["countryCode", "country"],
            where,
            _count: {
              _all: true,
            },
            orderBy: {
              _count: {
                countryCode: "desc",
              },
            },
            take: 10,
          }),
          prisma.visit.groupBy({
            by: ["city", "countryCode"],
            where: { ...where, city: { not: null } },
            _count: { _all: true },
            orderBy: {
              _count: {
                city: "desc",
              },
            },
            take: 100,
          }),
        ]),
      {
        maxRetries: 8,
        initialDelayMs: 3000,
        maxDelayMs: 15000,
        operationName: "fetch stats",
      },
    );

    return { totalVisits, visitsByCountry, mapData };
  } catch (e) {
    fastify.log.error(e);
    errorCount++;
    const isDbError =
      e instanceof Error &&
      (e.message.includes("connection") || e.message.includes("ECONNREFUSED"));
    reply.code(isDbError ? 503 : 500).send({
      error: isDbError
        ? "Service temporarily unavailable, please retry"
        : "Failed to fetch stats",
    });
  }
});

const start = async () => {
  try {
    await fastify.listen({ port: PORT, host: "0.0.0.0" });
    console.log(`Server listening on http://0.0.0.0:${PORT}`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};
start();
