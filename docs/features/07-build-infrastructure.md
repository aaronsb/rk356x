# Build Infrastructure Features

**Category:** Build Infrastructure
**Phase:** 6
**Priority:** P1 (High Priority)
**Dependencies:** Features 1-14 (Complete System)
**Status:** ✅ **COMPLETE** - Docker builds, GitHub Actions, artifact packaging

## Overview

These features establish reproducible build processes, automated CI/CD pipelines, and artifact packaging for reliable firmware delivery.

**Implementation:**
- Docker-based builds with Ubuntu 22.04 for reproducibility
- GitHub Actions CI/CD with config validation and full builds
- Automated artifact packaging and GitHub releases
- Three build workflows: local, local+release, remote

---

## Feature 15: Build Reproducibility Framework

**Status:** ⏸️ Planning
**Estimated Effort:** 5-7 days
**Owner:** TBD

### Description

Ensure that firmware builds are fully reproducible - identical inputs always produce identical outputs, enabling verification and debugging.

### User Stories

#### Story 15.1: Define build inputs and environment

**Tasks:**
- [ ] Document all build inputs:
  - [ ] Toolchain version (exact commit/tag)
  - [ ] BSP version and patches
  - [ ] Kernel version and configuration
  - [ ] U-Boot version and configuration
  - [ ] Debian/Ubuntu release and package versions
  - [ ] Application version
  - [ ] Build script versions
- [ ] Lock all external dependencies:
  - [ ] APT package versions
  - [ ] Python package versions
  - [ ] Git submodule commits
- [ ] Define build environment:
  - [ ] Host OS version
  - [ ] Required packages with versions
  - [ ] Environment variables
  - [ ] Build directory structure
- [ ] Create build environment container (Docker)
- [ ] Document environment in `docs/build-environment.md`
- [ ] Create environment setup script

**Acceptance Criteria:**
- All build inputs documented with exact versions
- Dependencies locked
- Build environment defined
- Docker container created
- Setup script functional
- Documentation complete

---

#### Story 15.2: Validate reproducible builds

**Tasks:**
- [ ] Perform clean build on developer machine
- [ ] Perform clean build on CI server
- [ ] Perform clean build on second developer machine
- [ ] Compare all build outputs:
  - [ ] Binary-level comparison of images
  - [ ] Generate checksums
  - [ ] Document any differences
- [ ] Identify and fix sources of non-determinism:
  - [ ] Timestamps in binaries
  - [ ] Random build order
  - [ ] Filesystem ordering
  - [ ] Hostname/username leakage
- [ ] Implement `SOURCE_DATE_EPOCH` for timestamps
- [ ] Re-run builds and verify byte-for-byte identical
- [ ] Document reproducibility in `docs/reproducible-builds.md`

**Acceptance Criteria:**
- Clean builds match exactly across environments
- Checksums identical
- Build process deterministic
- Non-determinism sources eliminated
- Reproducibility confirmed and documented

### Technical Notes

**Reproducibility Best Practices:**

1. **Fixed Timestamps:**
```bash
export SOURCE_DATE_EPOCH=1609459200  # Fixed date
```

2. **Deterministic Tar:**
```bash
tar --sort=name --mtime='@1609459200' --owner=0 --group=0 -czf output.tar.gz files/
```

3. **Sorted File Operations:**
```bash
find . -type f | sort | xargs process
```

4. **Docker for Consistency:**
```dockerfile
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
ENV SOURCE_DATE_EPOCH=1609459200
RUN apt-get update && apt-get install -y --no-install-recommends \
    package1=version1 \
    package2=version2
# ... exact versions for all packages
```

5. **Version Locks:**
```bash
# requirements.txt for Python
package1==1.2.3
package2==4.5.6

# package-lock.json for Node.js (auto-generated)
```

### Artifacts

- `docs/build-environment.md` - Environment documentation
- `docs/reproducible-builds.md` - Reproducibility documentation
- `docker/build-environment/Dockerfile` - Build container
- `scripts/setup-build-env.sh` - Environment setup
- `scripts/verify-build-reproducibility.sh` - Verification script
- `config/locked-versions.txt` - All version locks

---

## Feature 16: CI/CD Pipeline Construction

**Status:** ⏸️ Planning
**Estimated Effort:** 7-10 days
**Owner:** TBD

### Description

Build automated continuous integration and deployment pipeline for firmware builds, tests, and releases.

### User Stories

#### Story 16.1: Create automated firmware build pipeline

**Tasks:**
- [ ] Choose CI/CD platform (GitHub Actions, GitLab CI, Jenkins, etc.)
- [ ] Create pipeline configuration file
- [ ] Configure build triggers:
  - [ ] On commit to main branch
  - [ ] On pull request
  - [ ] On git tag (release)
  - [ ] Manual/scheduled builds
- [ ] Implement build stages:
  - [ ] Environment setup
  - [ ] Source checkout
  - [ ] Toolchain installation
  - [ ] U-Boot build
  - [ ] Kernel build
  - [ ] Rootfs build
  - [ ] Image assembly
  - [ ] Checksum generation
- [ ] Configure build matrix (multiple boards if needed)
- [ ] Implement caching for faster builds:
  - [ ] Toolchain cache
  - [ ] ccache for kernel/U-Boot
  - [ ] Debian package cache
- [ ] Document pipeline in `docs/ci-cd-pipeline.md`

**Acceptance Criteria:**
- Pipeline configured on CI/CD platform
- Builds trigger correctly
- All build stages functional
- Build completes successfully
- Build time reasonable (< 2 hours)
- Caching improves subsequent build times
- Documentation complete

---

#### Story 16.2: Add automated tests and notifications

**Tasks:**
- [ ] Add test stages to pipeline:
  - [ ] Build verification (image created)
  - [ ] Image structure tests
  - [ ] Checksum validation
  - [ ] Hardware test suite (if hardware-in-loop available)
- [ ] Configure test result reporting
- [ ] Implement notifications:
  - [ ] Email on build failure
  - [ ] Slack/Teams notification
  - [ ] GitHub/GitLab status checks
- [ ] Add artifact storage:
  - [ ] Upload build artifacts
  - [ ] Retention policy (30 days for branches, indefinite for releases)
- [ ] Configure deployment stage:
  - [ ] Deploy to artifact server
  - [ ] Create GitHub/GitLab release
  - [ ] Update latest firmware links
- [ ] Create build status badge
- [ ] Implement build metrics collection

**Acceptance Criteria:**
- Automated tests run on each build
- Test results reported in pipeline
- Notifications configured and working
- Artifacts uploaded automatically
- Releases created for tags
- Build status visible
- Metrics collected

### Pipeline Example (GitHub Actions)

```yaml
name: Build Firmware

on:
  push:
    branches: [main, develop]
  pull_request:
  release:
    types: [created]

jobs:
  build:
    runs-on: ubuntu-22.04
    strategy:
      matrix:
        board: [rock-3a, custom-board]

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Cache toolchain
        uses: actions/cache@v3
        with:
          path: ~/toolchain
          key: toolchain-${{ hashFiles('config/toolchain-version.txt') }}

      - name: Install dependencies
        run: ./scripts/setup-build-env.sh

      - name: Build U-Boot
        run: ./scripts/build-uboot.sh ${{ matrix.board }}

      - name: Build Kernel
        run: ./scripts/build-kernel.sh ${{ matrix.board }}

      - name: Build Rootfs
        run: sudo ./scripts/build-rootfs.sh ${{ matrix.board }}

      - name: Assemble Image
        run: sudo ./scripts/assemble-image.sh ${{ matrix.board }}

      - name: Run Tests
        run: ./scripts/verify-image.sh

      - name: Upload Artifacts
        uses: actions/upload-artifact@v3
        with:
          name: firmware-${{ matrix.board }}-${{ github.sha }}
          path: output/*.img.xz
          retention-days: 30
```

### Artifacts

- `docs/ci-cd-pipeline.md` - Pipeline documentation
- `.github/workflows/build.yml` - GitHub Actions config (or equivalent)
- `scripts/ci-build.sh` - CI build script
- `scripts/verify-image.sh` - Image verification script
- `config/ci-environment.yml` - CI environment definition

---

## Feature 17: Automated Artifact Packaging

**Status:** ⏸️ Planning
**Estimated Effort:** 3-5 days
**Owner:** TBD

### Description

Automate the creation and packaging of all update artifacts (SD updater, USB update package, partial update bundles).

### User Stories

#### Story 17.1: Automate creation of update bundles

**Tasks:**
- [ ] Create SD updater packaging script
- [ ] Create USB update packaging script
- [ ] Create partial update packaging script
- [ ] Implement version stamping in packages
- [ ] Add package signature generation
- [ ] Add package checksum generation
- [ ] Implement compression
- [ ] Create package manifests
- [ ] Add automated testing of packages
- [ ] Integrate into CI/CD pipeline
- [ ] Document packaging in `docs/artifact-packaging.md`

**Acceptance Criteria:**
- All update bundle types generated automatically
- Packages include correct firmware version
- Signatures generated
- Checksums generated
- Compression applied
- Packages tested automatically
- Integration with CI/CD complete

---

#### Story 17.2: Store bundles in repository

**Tasks:**
- [ ] Set up artifact storage:
  - [ ] Configure artifact server / S3 / GitHub releases
  - [ ] Define directory structure
  - [ ] Implement retention policy
- [ ] Implement artifact upload from CI/CD
- [ ] Create artifact download page/API
- [ ] Implement versioning scheme:
  - [ ] Naming convention (firmware-v1.2.3-board.img.xz)
  - [ ] Latest symlinks
  - [ ] Version manifest
- [ ] Add artifact metadata:
  - [ ] Build date
  - [ ] Git commit hash
  - [ ] Component versions
  - [ ] Release notes
- [ ] Create artifact index/catalog
- [ ] Implement artifact cleanup (old versions)

**Acceptance Criteria:**
- Artifact storage configured
- Upload from CI/CD functional
- Naming convention followed
- Latest versions easily identifiable
- Metadata included
- Catalog/index available
- Old artifacts cleaned up automatically

### Artifact Naming Convention

```
firmware-{version}-{board}-{date}.img.xz
  Example: firmware-v1.2.3-rock3a-20250115.img.xz

sd-updater-{version}-{board}-{date}.img.xz
  Example: sd-updater-v1.2.3-rock3a-20250115.img.xz

usb-update-{version}-{board}-{date}.zip
  Example: usb-update-v1.2.3-rock3a-20250115.zip

partial-update-{component}-{version}-{date}.tar.gz
  Example: partial-update-app-v1.2.3-20250115.tar.gz
```

### Artifacts

- `docs/artifact-packaging.md` - Packaging documentation
- `scripts/package-sd-updater.sh` - SD updater packager
- `scripts/package-usb-update.sh` - USB update packager
- `scripts/package-partial-update.sh` - Partial update packager
- `scripts/upload-artifacts.sh` - Artifact upload script
- `config/artifact-naming.txt` - Naming convention rules

---

## Phase Completion Criteria

Build Infrastructure phase is complete when:

- ✅ Build reproducibility achieved and verified
- ✅ All build inputs and environment documented
- ✅ Docker build environment created
- ✅ CI/CD pipeline functional
- ✅ Automated tests running
- ✅ Notifications configured
- ✅ Artifact packaging automated
- ✅ Artifact storage configured
- ✅ All documentation complete
- ✅ Engineering lead sign-off obtained

## Next Steps

After completing this phase:

1. Proceed to [Release Management](./08-release-management.md) (Features 18-19)
2. Establish release versioning
3. Complete technical documentation
4. Prepare for production releases
