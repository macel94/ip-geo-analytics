# Project Instructions

## Visitor Analytics Dashboard

This document outlines how to set up, run, and deploy the Visitor Analytics project.

## 🚀 Quick Start (Dev Container)

**Everything you need is pre-installed.**
This project includes a `.devcontainer` configuration. When opening in VS Code (or GitHub Codespaces), the environment automatically provides:
-   Node.js & npm
-   Docker & Docker Compose (Docker-in-Docker)
-   Azure CLI
-   Prisma CLI

### 1. Initialization
Open a terminal and run the setup script. This installs dependencies, starts the local Postgres database, and applies migrations.

```bash
./scripts/setup_local.sh
```

### 2. Start Development
Start both the Backend (Fastify) and Frontend (Vite) in a single command:

```bash
./scripts/start_dev.sh
```

-   **Frontend**: [http://localhost:5173](http://localhost:5173)
-   **Backend**: [http://localhost:3000](http://localhost:3000)

## 📂 Project Structure

```text
/
├── .devcontainer/    # VS Code Dev Container config
├── client/           # React + Vite application
├── server/           # Fastify + Prisma application
├── deploy/           # Azure Bicep & Deploy scripts
├── scripts/          # Helper scripts for local dev
└── docker-compose.yml # Local PostgreSQL definition
```

## 🛠 Manual Configuration

If you are **not** using the Dev Container, ensure you have:
1.  **Node.js v18+**
2.  **Docker Desktop** (running)
3.  **GeoIP Database**: Download `GeoLite2-City.mmdb` and place it in `/server/geoip/` (or root `geoip/` depending on mount).

## ☁️ Deployment

The project is designed to be deployed as a single Docker container on Azure Container Apps.

1.  **Build**: The `Dockerfile` in root builds the client and copies it to the server's static folder.
2.  **Deploy**:
    Modify `deploy/deploy.sh` with your subscription details and run:
    ```bash
    cd deploy
    ./deploy.sh
    ```
