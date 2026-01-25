# Testing Guide for Docker Package Visibility Fix

## Summary of Changes
This PR fixes the Azure Container Apps deployment failure by making Docker images on GitHub Container Registry (GHCR) public and configuring the infrastructure to use public images without authentication.

## Pre-Merge Testing (Optional)
Since these are infrastructure changes, the automated tests won't validate the fix. However, you can verify the workflow changes locally:

### 1. Validate Bicep Syntax
```bash
cd infra
az bicep build --file main.bicep
# Should complete without errors
```

### 2. Test the Make Package Public Workflow
This can only be tested after merging (requires the package to exist):
```bash
# After merge: Go to Actions → Make Docker Package Public → Run workflow
```

## Post-Merge Testing (Required)

### Step 1: Make the Existing Package Public
After merging this PR, the package needs to be made public. Choose one method:

#### Option A: Automatic (Recommended)
Trigger a rebuild of the main branch to create a new public image:
```bash
git checkout main
git pull
git commit --allow-empty -m "Trigger rebuild to make package public"
git push origin main
```

This will:
1. Trigger the `docker-build.yml` workflow
2. Build and push the Docker image
3. Automatically make the package public via the new step

#### Option B: Manual Workflow
1. Go to: Actions → Make Docker Package Public
2. Click "Run workflow"
3. Leave default values
4. Click "Run workflow" button

#### Option C: GitHub UI
1. Go to: https://github.com/users/macel94/packages/container/ip-geo-analytics/settings
2. Scroll to "Danger Zone"
3. Click "Change visibility"
4. Select "Public"
5. Confirm

### Step 2: Verify Package is Public
```bash
# This should work without `docker login`
docker pull ghcr.io/macel94/ip-geo-analytics:latest
```

Expected: Image pulls successfully without authentication

### Step 3: Test Azure Deployment
Trigger the deployment workflow:
```bash
# Via GitHub CLI
gh workflow run deploy-azure-container-apps.yml -f environment=staging

# Or via GitHub UI
# Go to: Actions → Deploy to Azure Container Apps → Run workflow
# Select environment: staging
# Click "Run workflow"
```

### Step 4: Monitor Deployment
Watch the workflow run:
```bash
gh run watch

# Or view in browser:
# https://github.com/macel94/ip-geo-analytics/actions
```

### Step 5: Verify Deployment Success
Check that:
1. ✅ Deployment job completes successfully
2. ✅ Verify Deployment job shows health check passing
3. ✅ No "ImagePullBackOff" or "403 Forbidden" errors in logs
4. ✅ Application is accessible at the deployed URL

### Step 6: Verify Application Health
```bash
# Get the app URL from workflow output or Azure portal
APP_URL="https://app--<hash>.azurecontainerapps.io"

# Test health endpoint
curl $APP_URL/health
# Expected: {"status":"ok","database":"connected"}

# Test ready endpoint  
curl $APP_URL/ready
# Expected: {"status":"ready"}
```

## Expected Outcomes

### Before Fix
- ❌ Azure deployment fails
- ❌ Container logs show: "failed to authorize: failed to fetch oauth token: 403 Forbidden"
- ❌ Container status: ImagePullBackOff

### After Fix
- ✅ Azure deployment succeeds
- ✅ Container pulls image without authentication errors
- ✅ Container status: Running
- ✅ Health checks pass
- ✅ Application is accessible

## Troubleshooting

### If Package Visibility Fails to Update
**Symptom**: The "Make package public" step fails in the workflow

**Solutions**:
1. Verify the package exists: https://github.com/macel94/packages
2. Try the manual workflow: "Make Docker Package Public"
3. Use the GitHub UI method (Option C above)

### If Deployment Still Fails After Package is Public
**Symptom**: ImagePullBackOff persists

**Diagnostic Steps**:
1. Verify package is actually public:
   ```bash
   docker pull ghcr.io/macel94/ip-geo-analytics:sha-<commit-hash>
   ```
2. Check Azure Container Apps logs for specific error
3. Verify the Bicep deployment didn't include registry credentials:
   ```bash
   az containerapp show -n app -g rg-ip-geo-analytics --query 'properties.configuration.registries'
   # Should return: [] (empty array)
   ```

### If Health Checks Fail
This indicates a different issue (not related to image pull):
1. Check container logs: `az containerapp logs show -n app -g rg-ip-geo-analytics --tail 50`
2. Verify database connection (PostgreSQL may need time to wake up from scale-to-zero)
3. Check that DATABASE_URL environment variable is correctly set

## Files Changed
- `.github/workflows/docker-build.yml` - Auto-publishes packages
- `.github/workflows/deploy-azure-container-apps.yml` - Removes auth for public images
- `.github/workflows/make-package-public.yml` - Manual workflow for making packages public
- `infra/main.bicep` - Makes registry credentials optional
- `docs/DOCKER_VISIBILITY_FIX.md` - Documentation
- `docs/TESTING.md` - This file
