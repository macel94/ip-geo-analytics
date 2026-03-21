# One Dockerfile, one deployable app

<div class="grid grid-cols-2 gap-10 pt-6">
  <div>
    <ul>
      <li>Multi-stage build compiles the Vite client and the Fastify server</li>
      <li>The final runtime image serves the built SPA from the backend container</li>
      <li>The same image is used for local Azure-like testing and cloud deployment</li>
    </ul>
  </div>
  <div class="code-panel">

```dockerfile
FROM node:25-alpine AS client-builder
FROM node:25-alpine AS server-builder
FROM node:25-alpine
```

  </div>
</div>

---
layout: two-cols
layoutClass: gap-12
---

# Continuous E2E validation

- GitHub Actions boots PostgreSQL as a service container
- The E2E job runs inside the official Playwright container image
- Browser dependencies are already baked in, so CI stays consistent
- Reports and traces are uploaded on every run

::right::

# Why that helped

- Less CI setup noise
- Fewer environment-specific browser issues
- Easier version pinning between Playwright and CI image
- A cleaner story to explain and maintain

<!--
Emphasize that the browser environment is treated as infrastructure, not as a mutable CI host.
-->
