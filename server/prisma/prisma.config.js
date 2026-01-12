"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const config_1 = require("@prisma/config");
const dotenv_1 = __importDefault(require("dotenv"));
const path_1 = __importDefault(require("path"));
// Load environment variables explicitly
dotenv_1.default.config({ path: path_1.default.join(__dirname, "../.env") });
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
    throw new Error("DATABASE_URL is required for Prisma configuration.");
}
exports.default = (0, config_1.defineConfig)({
    schema: "./schema.prisma",
    datasource: {
        url: databaseUrl,
    },
});
