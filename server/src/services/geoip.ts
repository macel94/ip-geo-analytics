import fs from "fs";
import path from "path";
import { Reader, ReaderModel } from "@maxmind/geoip2-node";

// Singleton for GeoIP Reader
let reader: ReaderModel | null = null;

// Look for GeoIP database in multiple locations for flexibility
const POSSIBLE_PATHS = [
  path.join(process.cwd(), "geoip", "GeoLite2-City.mmdb"), // CWD/geoip (local dev)
  path.join(process.cwd(), "..", "geoip", "GeoLite2-City.mmdb"), // Parent dir (when CWD is server/)
  "/app/geoip/GeoLite2-City.mmdb", // Absolute path in Docker
  path.join(__dirname, "../../geoip", "GeoLite2-City.mmdb"), // Relative to compiled file
];

function findDbPath(): string | null {
  for (const dbPath of POSSIBLE_PATHS) {
    if (fs.existsSync(dbPath)) {
      return dbPath;
    }
  }
  return null;
}

export async function initGeoIp() {
  if (reader) return reader;

  const dbPath = findDbPath();

  if (!dbPath) {
    console.warn("GeoIP database not found. Searched paths:", POSSIBLE_PATHS);
    return null;
  }

  try {
    reader = await Reader.open(dbPath);
    console.log("GeoIP database loaded from:", dbPath);
  } catch (e) {
    console.error("Failed to load GeoIP DB from", dbPath, e);
  }
  return reader;
}

export function getGeoData(ip: string) {
  if (!reader) return null;
  try {
    const response = reader.city(ip);
    return {
      city: response.city?.names?.en || null,
      country: response.country?.names?.en || null,
      countryCode: response.country?.isoCode || null,
    };
  } catch (error) {
    // IP might not be in the database (e.g. localhost)
    return null;
  }
}
// Note: ASN lookup usually requires a separate DB (GeoLite2-ASN.mmdb) using the ASN reader method.
// For simplicity in this demo, we'll stick to City/Country or mock ASN if using City DB only.
