import { defineConfig } from "@prisma/config";
import dotenv from "dotenv";
import path from "path";

// Load environment variables explicitly
dotenv.config({ path: path.join(__dirname, "../.env") });

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl) {
  throw new Error("DATABASE_URL is required for Prisma configuration.");
}

export default defineConfig({
  schema: "./schema.prisma",
  datasource: {
    url: databaseUrl,
  },
});
