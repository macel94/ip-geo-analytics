# Local development became boring in a good way

<div class="grid grid-cols-2 gap-10 pt-6">
  <div>
    <div class="eyebrow">Dev Container</div>
    <ul>
      <li>Node, Docker-in-Docker, Azure CLI, Prisma CLI are preinstalled</li>
      <li>Ports for API, frontend, and Postgres are already forwarded</li>
      <li>New environments start from the same baseline every time</li>
    </ul>
  </div>
  <div>
    <div class="eyebrow">Docker Compose</div>
    <ul>
      <li>Local Postgres runs as a disposable container</li>
      <li>`./scripts/setup_local.sh` wires dependencies, DB, env, and Prisma</li>
      <li>Application code stays on the host repo, state lives in the DB container</li>
    </ul>
  </div>
</div>

---
layout: two-cols
layoutClass: gap-12
---

# What this removed

- “Works on my machine” setup drift
- Manual installation checklists
- Local database snowflakes
- Slow onboarding for demos or contributors

::right::

# What we gained

- Reproducible setup
- Faster first run
- Easier pairing and reviews
- A dev experience close to production habits
