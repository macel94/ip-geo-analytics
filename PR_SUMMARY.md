# Fix: Azure Container Apps Image Pull Failure (403 Forbidden)

## 🔍 Problem
Azure Container Apps deployment was failing with:
```
failed to authorize: failed to fetch oauth token: 
unexpected status from GET request to https://ghcr.io/token?
scope=repository%3Amacel94%2Fip-geo-analytics%3Apull&service=ghcr.io: 
403 Forbidden
```

## 🎯 Root Cause
- **GHCR packages are private by default**, even for public repositories
- Azure Container Apps cannot use `GITHUB_TOKEN` (workflow-scoped) for authentication
- The deployment was trying to pull a private image without valid credentials

## ✅ Solution
Make Docker images **public** on GHCR and configure infrastructure to work with public images:

### 1. Automatic Package Publishing (`.github/workflows/docker-build.yml`)
- Added step to automatically set package visibility to public after push
- Uses GitHub API to update package settings
- Runs on every push to main branch

### 2. Infrastructure Support (` infra/main.bicep`)
- Made registry credentials **optional**
- If credentials are empty → assume public image, no auth needed
- Maintains backward compatibility for private images

### 3. Deployment Configuration (`.github/workflows/deploy-azure-container-apps.yml`)
- Removed registry credentials from deployment (not needed for public images)
- Simplified deployment parameters

### 4. Manual Workflow (`.github/workflows/make-package-public.yml`)
- Provides a way to manually make existing packages public
- Useful for one-time fixes or troubleshooting

### 5. Documentation
- `docs/DOCKER_VISIBILITY_FIX.md` - Explains the issue and solutions
- `docs/TESTING.md` - Post-merge testing guide

## 📋 What Happens Next

### After Merge
1. **Make the existing package public** (choose one):
   - **Option A** (Recommended): Trigger rebuild of main
     ```bash
     git commit --allow-empty -m "Trigger rebuild to make package public"
     git push origin main
     ```
   - **Option B**: Run "Make Docker Package Public" workflow manually
   - **Option C**: Change visibility via GitHub UI

2. **Verify package is public**:
   ```bash
   docker pull ghcr.io/macel94/ip-geo-analytics:latest
   # Should work without docker login
   ```

3. **Re-run Azure deployment**:
   ```bash
   gh workflow run deploy-azure-container-apps.yml -f environment=staging
   ```

4. **Verify deployment succeeds** - see `docs/TESTING.md` for details

## 🔒 Security
✅ CodeQL scan passed - no vulnerabilities
- Making packages public is the **intended solution** for this use case
- No secrets or credentials exposed
- Public access aligns with public repository model

## 📚 References
- [GitHub Packages Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- Issue: https://github.com/macel94/ip-geo-analytics/commit/69389986096ca84b169c9175a6cf7d98310d2ea3/checks

## 💡 Key Learnings
1. GHCR packages are private by default, regardless of repository visibility
2. `GITHUB_TOKEN` is workflow-scoped and cannot be used outside GitHub Actions
3. For public projects, making images public simplifies deployment
4. Azure Container Apps can pull public images without any authentication
