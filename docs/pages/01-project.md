# The project in one slide

<div class="grid grid-cols-2 gap-10 pt-6">
  <div>
    <div class="eyebrow">Problem</div>
    <h2 class="!mt-2">Collect visit data without building a giant platform</h2>
    <ul>
      <li>Fastify API receives tracking events</li>
      <li>Prisma writes visit data into PostgreSQL</li>
      <li>React + Vite dashboard shows maps and aggregates</li>
      <li>GeoIP enrichment adds location context</li>
    </ul>
  </div>
  <div>
    <div class="eyebrow">Why containers mattered</div>
    <ul>
      <li>Same tooling for every contributor</li>
      <li>Same packaging model from laptop to cloud</li>
      <li>Same test environment on every CI run</li>
      <li>Cheap deployment with scale-to-zero</li>
    </ul>
  </div>
</div>

<!--
Open with the product, then immediately frame containers as the delivery backbone.
-->

---
layout: center
class: text-left
---

# Container map

```mermaid
flowchart LR
    A[Dev Container] --> B[App Code]
    C[Docker Compose\nPostgres] --> B
    B --> D[Dockerfile\nSingle app image]
    D --> E[Playwright CI]
    D --> F[Azure Container Apps]
    G[Azure Files\nPersistent Postgres data] --> F
```
