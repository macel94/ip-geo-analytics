# Docker Image Visibility Fix

## Problem
Azure Container Apps deployment fails with:
```
failed to authorize: failed to fetch oauth token: 
unexpected status from GET request to https://ghcr.io/token?scope=repository%3Amacel94%2Fip-geo-analytics%3Apull&service=ghcr.io: 403 Forbidden
```

## Root Cause
- GitHub Container Registry (GHCR) packages are **private by default**, even for public repositories
- Azure Container Apps cannot authenticate using GitHub workflow tokens (`GITHUB_TOKEN`)
- The image needs to be public for Azure to pull it without credentials

## Solution Implemented

### 1. Automatic Package Visibility (Future Builds)
The Docker build workflow now automatically makes packages public after pushing:
- File: `.github/workflows/docker-build.yml`
- Step: "Make package public"
- This runs on every push to main branch

### 2. Infrastructure Changes
Modified Azure deployment to support public images:
- File: `infra/main.bicep`
- Registry credentials are now optional (empty = public image)
- Deployment workflow no longer passes credentials for public images

### 3. Manual Package Visibility (Existing Images)
For existing packages that are already private, use one of these methods:

#### Option A: Run the Manual Workflow
```bash
# Via GitHub UI: Actions → Make Docker Package Public → Run workflow
# Or via CLI:
gh workflow run make-package-public.yml
```

#### Option B: Rebuild Main Branch
Trigger a rebuild of the main branch to create a new public image:
```bash
# This will trigger docker-build.yml which includes the make-public step
git commit --allow-empty -m "Trigger rebuild to make package public"
git push origin main
```

#### Option C: Manual Configuration via GitHub UI
1. Go to: https://github.com/users/{OWNER}/packages/container/{PACKAGE_NAME}/settings
   - Replace `{OWNER}` with your GitHub username
   - Replace `{PACKAGE_NAME}` with your package name (e.g., `ip-geo-analytics`)
2. Scroll to "Danger Zone"
3. Click "Change visibility"
4. Select "Public"
5. Confirm the change

## Verification
After making the package public, verify you can pull it without authentication:
```bash
# Should work without docker login
# Replace with your actual owner and package name
docker pull ghcr.io/{OWNER}/{PACKAGE_NAME}:latest
```

## Next Steps
After the package is public:
1. Re-run the Azure deployment: `gh workflow run deploy-azure-container-apps.yml`
2. Azure Container Apps should successfully pull the image
3. Deployment should complete successfully
