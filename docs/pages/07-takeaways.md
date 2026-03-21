# What containers changed across the lifecycle

| Stage | Container benefit |
| --- | --- |
| Development | same tools, same ports, same onboarding path |
| Local infrastructure | disposable Postgres with persistent local volume |
| Build | one image for the app instead of manual deployment steps |
| Testing | stable Playwright runtime for E2E automation |
| Deployment | scale-to-zero app + persistent PostgreSQL state |

## Final message

This project is not just containerized at the end.
It is **container-shaped from day one**: dev environment, local services, CI runtime, and cloud deployment all use the same idea.

## Demo flow

1. Open in the devcontainer
2. Start Postgres with Compose
3. Run the app locally
4. Show the E2E workflow
5. End on Azure Container Apps + Azure Files
