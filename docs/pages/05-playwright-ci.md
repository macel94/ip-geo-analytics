# Playwright containers made E2E runs reproducible

<div class="grid grid-cols-2 gap-8 mt-8">
<div>

## CI shape

- GitHub Actions job runs in `mcr.microsoft.com/playwright:v1.58.2-noble`
- PostgreSQL is started as a service container
- tests still exercise the real app stack end to end
- HTML reports and test results are uploaded as artifacts

</div>
<div>

## Why this matters

- browser binaries and OS dependencies are pre-baked
- CI behaves more like a controlled lab than a mutable VM
- the Playwright image version is pinned to the project version
- failures are easier to reproduce because the runtime is explicit

</div>
</div>

## Official guidance we followed

Playwright's docs recommend using the official Docker image for testing/dev and pinning the image version.

<!--
Source:
- .github/workflows/e2e-tests.yml
- playwright.config.ts
- https://playwright.dev/docs/docker
Note for speaker: mention that the app under test still runs from repo code; the container standardizes the browser/test runtime.
-->
