import fs from 'fs';
import path from 'path';
import { Reader, ReaderModel } from '@maxmind/geoip2-node';

// Singleton for GeoIP Reader
let reader: ReaderModel | null = null;
const DB_PATH = path.join(process.cwd(), 'geoip', 'GeoLite2-City.mmdb'); // Assuming file is mounted here

export async function initGeoIp() {
  if (reader) return reader;
  
  // practical note: in production, you might want to download this from a URL or S3 bucket on startup 
  // or use the maxmind-db library to watch for updates.
  // For this demo, we assume the .mmdb file is present.
  
  try {
    if (fs.existsSync(DB_PATH)) {
        reader = await Reader.open(DB_PATH);
        console.log('GeoIP database loaded.');
    } else {
        console.warn('GeoIP database not found at', DB_PATH);
    }
  } catch(e) {
      console.error("Failed to load GeoIP DB", e);
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
