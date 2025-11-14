# GitHub Actions Workflow Guide

This document explains how our GitHub Actions CI/CD workflow works for building RK356X images.

## Workflow Overview

**File:** `.github/workflows/build-image.yml`

The workflow supports two build modes:
1. **Config-only** (default): Validates configuration in ~2 minutes
2. **Full build**: Compiles everything in ~60 minutes

## Trigger Modes

### 1. Automatic (Push to main/develop)

```bash
git push origin main
```

**What happens:**
- ✅ Validates Buildroot configuration
- ✅ Checks defconfig loads correctly
- ❌ Does NOT build full image (too expensive)
- Runtime: ~2 minutes

### 2. Manual Trigger (Testing)

```bash
gh workflow run "Build RK356X Image" \
  --field board=rk3568_jvl \
  --field build_type=full-build
```

**What happens:**
- ✅ Full Buildroot compilation
- ✅ Uploads artifacts (30-day retention)
- ❌ Does NOT create GitHub release
- Runtime: ~60 minutes

### 3. Tag-based (Production Releases)

```bash
# Using the release script (recommended)
./scripts/release.sh patch

# Or manually
echo "0.1.1" > VERSION
git add VERSION
git commit -m "Bump version to 0.1.1"
git tag -a v0.1.1 -m "Release v0.1.1"
git push && git push --tags
```

**What happens:**
- ✅ Full Buildroot compilation
- ✅ Creates GitHub Release with artifacts
- ✅ Auto-generates release notes
- ✅ Permanent artifact storage
- Runtime: ~60 minutes

## Workflow Steps Explained

### Step 1: Free Disk Space

```yaml
- name: Free disk space
  run: |
    sudo rm -rf /usr/share/dotnet
    sudo rm -rf /opt/ghc
    sudo rm -rf "$AGENT_TOOLSDIRECTORY"
```

**Why:** GitHub runners have limited space (~30GB free). Buildroot needs ~10GB. We remove unused Microsoft and Haskell tools to free up ~20GB.

### Step 2: Install Dependencies

```yaml
- name: Install Buildroot dependencies
  run: |
    sudo apt-get install -y \
      build-essential libssl-dev libncurses-dev \
      bc rsync file wget cpio unzip python3 git
```

**Why:** These are required by Buildroot for compilation, extraction, and package building.

### Step 3: Set Build Configuration

```yaml
- name: Set build configuration
  run: |
    if [[ "${{ github.ref }}" == refs/tags/* ]]; then
      BUILD_TYPE="full-build"
    else
      BUILD_TYPE="${{ github.event.inputs.build_type || 'config-only' }}"
    fi
```

**Logic:**
- Tags → Always `full-build`
- Manual trigger → Use selected type
- Push events → Default to `config-only`

### Step 4: Cache Buildroot Downloads

```yaml
- name: Cache Buildroot downloads
  uses: actions/cache@v4
  with:
    path: buildroot/dl
    key: buildroot-dl-${{ hashFiles('external/jvl/configs/*') }}
```

**Why:** Source packages (~500MB) are cached between builds. Saves ~5-10 minutes on subsequent builds.

**Cache invalidation:** When defconfig changes, cache key changes, forcing re-download.

### Step 5: Download and Extract Buildroot

```yaml
- name: Download and extract Buildroot
  run: |
    wget -q https://buildroot.org/downloads/buildroot-2024.02.3.tar.gz
    tar xzf buildroot-2024.02.3.tar.gz
    # Handle cache conflict
    if [ -d buildroot/dl ]; then
      mv buildroot/dl dl_cache
    fi
    rm -rf buildroot
    mv buildroot-2024.02.3 buildroot
    if [ -d dl_cache ]; then
      mv dl_cache buildroot/dl
    fi
```

**Important:** The cache creates `buildroot/dl` before extraction. We must:
1. Save the cached `dl` directory
2. Remove `buildroot` directory
3. Rename extracted directory to `buildroot`
4. Restore cached `dl` directory

Without this, `mv` would nest directories incorrectly.

### Step 6: Load Configuration

```yaml
- name: Load configuration
  env:
    BR2_EXTERNAL: ${{ github.workspace }}/external/jvl
  run: |
    cd buildroot
    make rk3568_jvl_defconfig
```

**BR2_EXTERNAL:** Points Buildroot to our external tree containing custom defconfigs.

### Step 7: Validate Configuration

```yaml
- name: Validate configuration
  env:
    BR2_EXTERNAL: ${{ github.workspace }}/external/jvl
  run: |
    cd buildroot
    make show-info
```

**What it checks:** Configuration is valid, packages are available, dependencies are satisfied.

### Step 8: Build (Conditional)

```yaml
- name: Build (if full-build)
  if: steps.config.outputs.build_type == 'full-build'
  env:
    BR2_EXTERNAL: ${{ github.workspace }}/external/jvl
  run: |
    cd buildroot
    make -j$(nproc)
  timeout-minutes: 120
```

**Parallelism:** Uses all available cores (`$(nproc)` = 4 on GitHub runners)

**Timeout:** Kills build after 120 minutes (safety mechanism)

### Step 9: Upload Artifacts

```yaml
- name: Upload build artifacts
  if: steps.config.outputs.build_type == 'full-build'
  uses: actions/upload-artifact@v4
  with:
    name: buildroot-rk3568_jvl-${{ github.sha }}
    path: |
      buildroot/output/images/*.tar.gz
      buildroot/output/images/Image
      buildroot/output/images/*.dtb
    retention-days: 30
```

**Retention:** Artifacts are deleted after 30 days to save storage.

**Naming:** Includes git SHA for traceability.

### Step 10: Create Release (Tags Only)

```yaml
- name: Create release
  if: startsWith(github.ref, 'refs/tags/')
  uses: softprops/action-gh-release@v1
  with:
    files: |
      buildroot/output/images/rk356x-*.tar.gz
      buildroot/output/images/rootfs.tar.gz
      buildroot/output/images/Image
      buildroot/output/images/*.dtb
    generate_release_notes: true
```

**Release notes:** Automatically generated from commits since last tag.

**Artifact storage:** Permanent (not subject to 30-day deletion).

## Monitoring Builds

### Watch Active Build

```bash
gh run watch <run-id>
```

### View Recent Runs

```bash
gh run list --limit 10
```

### View Failed Run Logs

```bash
gh run view <run-id> --log-failed
```

### Cancel Running Build

```bash
gh run cancel <run-id>
```

## Cost Optimization

GitHub Actions provides **2,000 minutes/month free** for private repos, **unlimited for public repos**.

Our workflow:
- Config-only: ~2 minutes (✅ cheap)
- Full build: ~60 minutes (⚠️ expensive on private repos)

**Best practices:**
1. Use config-only for regular pushes
2. Use full builds only for releases
3. Test locally when possible
4. Cancel failed builds early

## Troubleshooting

### Build Fails: "No space left on device"

**Cause:** GitHub runners have ~14GB free after our cleanup

**Solution:** Reduce build size by disabling packages in defconfig

### Build Fails: "make: *** No rule to make target"

**Cause:** Buildroot directory structure is wrong

**Check:** Step 5 logs - verify Makefile exists after extraction

### Build Timeout (120 minutes)

**Cause:** Build is stuck or too slow

**Solutions:**
- Check for download issues (slow mirrors)
- Reduce parallelism if OOM errors occur
- Disable ccache temporarily

### Artifacts Not Uploaded

**Cause:** Build step failed or no files match pattern

**Check:**
```bash
gh run view <run-id> --log
# Look for "Upload build artifacts" step
```

## Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `BUILDROOT_VERSION` | `2024.02.3` | Buildroot version to download |
| `BR2_EXTERNAL` | `$GITHUB_WORKSPACE/external/jvl` | Path to external tree |
| `GITHUB_WORKSPACE` | `/home/runner/work/rk356x/rk356x` | Repository root |

## See Also

- [Build System Guide](BUILD.md)
- [Release Process](../RELEASES.md)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
