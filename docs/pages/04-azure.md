# Azure Container Apps fit the project shape

<div class="grid grid-cols-2 gap-10 pt-6">
  <div>
    <div class="eyebrow">App container</div>
    <ul>
      <li>External HTTPS ingress</li>
      <li>Scale from 0 to a few replicas</li>
      <li>Good fit for low-volume personal analytics</li>
    </ul>
  </div>
  <div>
    <div class="eyebrow">PostgreSQL container</div>
    <ul>
      <li>Runs privately inside the same environment</li>
      <li>Uses Azure Files for persisted data</li>
      <li>Can restart or scale back in without losing the database</li>
    </ul>
  </div>
</div>

---
layout: center
---

# The key production trade-off

<div class="max-w-4xl mx-auto grid grid-cols-3 gap-6 pt-8 text-left">
  <div class="card">
    <div class="eyebrow">Cheap</div>
    <p>Scale-to-zero keeps idle cost tiny.</p>
  </div>
  <div class="card">
    <div class="eyebrow">Simple</div>
    <p>One app image, one IaC stack, one place to reason about runtime.</p>
  </div>
  <div class="card">
    <div class="eyebrow">Stateful enough</div>
    <p>Persistent storage lets the demo survive restarts without adopting a managed DB yet.</p>
  </div>
</div>
