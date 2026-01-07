import "dotenv/config";
import Fastify, { FastifyRequest } from "fastify";
import path from "path";
import fastifyStatic from "@fastify/static";
import fastifyCors from "@fastify/cors";
import { PrismaClient } from "@prisma/client";
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

const prisma = new PrismaClient({ datasourceUrl: databaseUrl });

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
  site_id: string;
  referrer?: string;
}

// 1. Tracking Endpoint
fastify.post<{ Body: TrackBody }>("/api/track", async (request, reply) => {
  const { site_id, referrer } = request.body;
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

  try {
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
    return { success: true };
  } catch (e) {
    request.log.error(e);
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
