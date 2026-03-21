# Devcontainers removed setup friction

<div class="grid grid-cols-2 gap-8 mt-8">
<div>

## What is preinstalled

- Node 24 base image
- Docker-in-Docker
- Azure CLI
- GitHub CLI
- Prisma, Docker, Bicep, ESLint, Prettier VS Code extensions

</div>
<div>

## What that changed

- new contributors open the repo and get the same toolchain
- Docker commands work inside the workspace
- cloud and infra commands are already available
- ports `3000`, `5173`, and `5432` are forwarded up front

</div>
</div>

## Repo proof

- image: `mcr.microsoft.com/devcontainers/typescript-node:24-bookworm`
- post-create command points developers to `./scripts/setup_local.sh`

<!--
Source: .devcontainer/devcontainer.json
Best-practice angle: devcontainers turn "works on my machine" into a checked-in environment contract.
-->
