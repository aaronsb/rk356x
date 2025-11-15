# Quick Reference - Build Actions

## ⚠️ Important: Preventing Accidental Long Builds

**By default, pushing to `main` or `develop` does NOT trigger a full build!**

This prevents accidentally burning 60 minutes of GitHub Actions time on every push or merge.

## What Happens When You Push?

```bash
git push origin main
```

**Result:** ✅ **Config-only validation** (~2 minutes)
- Checks defconfig loads correctly
- Validates Buildroot configuration
- Does NOT compile kernel, toolchain, or packages
- Does NOT create artifacts

## How to Trigger a Full Build

### Option 1: Create a Release (Recommended)

```bash
./scripts/release.sh patch
```

**Result:**
- ✅ Full build (~60 minutes)
- ✅ Creates GitHub Release
- ✅ Permanent artifacts
- ✅ Auto-generated release notes

### Option 2: Manual Workflow Trigger

```bash
gh workflow run "Build RK356X Image" \
  --field board=rk3568_jvl \
  --field build_type=full-build
```

**Result:**
- ✅ Full build (~60 minutes)
- ✅ Artifacts (30-day retention)
- ❌ No GitHub Release created

### Option 3: Local Build

```bash
cd buildroot
BR2_EXTERNAL=../external/custom make -j$(nproc)
```

**Result:**
- ✅ Full build (~35-60 minutes on your machine)
- ✅ No GitHub Actions minutes used
- ✅ Immediate local testing

## Summary Table

| Action | Trigger | Duration | Artifacts | Use Case |
|--------|---------|----------|-----------|----------|
| `git push` | Automatic | 2 min | None | Normal development |
| Release script | Manual | 60 min | Permanent | Production releases |
| Workflow dispatch | Manual | 60 min | 30 days | Testing/debugging |
| Local build | Manual | 35-60 min | Local only | Development/testing |

## Safety Mechanisms

1. **Default is config-only** - Prevents accidental long builds
2. **Tags force full builds** - Ensures releases are always built
3. **Manual override required** - Full builds need explicit action
4. **120-minute timeout** - Kills runaway builds
5. **30-day artifact retention** - Prevents storage bloat

## Common Workflows

### Daily Development
```bash
# Make changes
vim external/custom/configs/rk3568_custom_defconfig

# Test locally (optional)
cd buildroot && BR2_EXTERNAL=../external/custom make -j$(nproc)

# Push changes
git add .
git commit -m "Update defconfig"
git push  # ← Only 2 minutes, config validation
```

### Creating a Release
```bash
# Use the release script
./scripts/release.sh patch  # v0.1.0 → v0.1.1

# Or do it manually
echo "0.2.0" > VERSION
git add VERSION
git commit -m "Bump version to 0.2.0"
git tag -a v0.2.0 -m "Release v0.2.0"
git push && git push --tags  # ← Triggers 60-min build
```

### Testing Build Changes
```bash
# Option 1: Local (fastest feedback)
cd buildroot
BR2_EXTERNAL=../external/custom make -j$(nproc)

# Option 2: GitHub Actions (test workflow)
gh workflow run "Build RK356X Image" \
  --field board=rk3568_jvl \
  --field build_type=full-build

# Wait and watch
gh run watch --exit-status
```

## Monitoring Builds

```bash
# List recent runs
gh run list --limit 5

# Watch active build
gh run watch <run-id>

# View logs
gh run view <run-id> --log

# Cancel if needed
gh run cancel <run-id>
```

## Cost Awareness

**GitHub Actions Free Tier:**
- Public repos: Unlimited minutes
- Private repos: 2,000 minutes/month

**Our builds:**
- Config-only: 2 min (safe to run frequently)
- Full build: 60 min (33 builds/month limit on private repos)

## When in Doubt

**Ask yourself:**
- Am I making a release? → Use `./scripts/release.sh`
- Am I testing workflow changes? → Use `gh workflow run`
- Am I developing/debugging? → Build locally
- Am I just pushing code? → Just push, config-only will run

**The workflow is designed to be safe by default!**
