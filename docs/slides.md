---
theme: default
title: From Dev Container to Scale-to-Zero
info: |
  Technical talk material for the ip-geo-analytics project.
  Focused on how containers improved development, testing, delivery, and operations.
class: text-center
drawings:
  persist: false
transition: slide-left
duration: 20min
mdc: true
---

# From Dev Container to Scale-to-Zero

## How containers shaped `ip-geo-analytics`

Fastify + Prisma + React/Vite + PostgreSQL + Playwright + Azure Container Apps

<div class="mt-10 text-sm opacity-70">
  Repo anchors: <code>.devcontainer/</code>, <code>Dockerfile</code>, <code>docker-compose*.yml</code>, <code>.github/workflows/</code>, <code>infra/main.bicep</code>
</div>

<!--
The goal of this talk is to show one coherent container story:
1) same tooling for every contributor,
2) same packaging model for local/prod,
3) reproducible E2E execution in CI,
4) cost-aware deployment with persistent DB storage.
-->

---
src: ./pages/01-agenda.md
---

---
src: ./pages/02-project-shape.md
---

---
src: ./pages/03-devcontainer.md
---

---
src: ./pages/04-build-run.md
---

---
src: ./pages/05-playwright-ci.md
---

---
src: ./pages/06-azure-container-apps.md
---

---
src: ./pages/07-takeaways.md
---
