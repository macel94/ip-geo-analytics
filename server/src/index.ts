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
const pool = new pg.Pool({ connectionString: databaseUrl });
const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter });

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
fastify.get("/health", async (request, reply) => {
  try {
    // Check database connectivity
    await prisma.$queryRaw`SELECT 1`;
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
fastify.get("/ready", async (request, reply) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return { status: "ready" };
  } catch (error) {
    reply.code(503);
    return { status: "not ready" };
  }
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

  // GeoIP Lookup
  const geo = getGeoData(ip) || {
    city: null,
    country: null,
    countryCode: null,
  };

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
    await trackVisit(request, resolvedSiteId, referrer);
    return { success: true };
  } catch (e) {
    request.log.error(e);
    errorCount++;
    reply.code(500).send({ error: "Tracking failed" });
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
    await trackVisit(request, resolvedSiteId, referrer);
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
    reply.code(500).send({ error: "Tracking failed" });
  }
});

// Analytics Dashboard Endpoints
fastify.get("/api/stats", async (request, reply) => {
  const { site_id } = request.query as { site_id?: string };
  const where = site_id ? { site_id } : {};

  const [totalVisits, visitsByCountry] = await Promise.all([
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
  ]);

  // Simplified Map Data (Density by City)
  const mapData = await prisma.visit.groupBy({
    by: ["city", "countryCode"],
    where: { ...where, city: { not: null } },
    _count: { _all: true },
    orderBy: {
      _count: {
        city: "desc",
      },
    },
    take: 100, // Limit for performance
  });

  return { totalVisits, visitsByCountry, mapData };
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
