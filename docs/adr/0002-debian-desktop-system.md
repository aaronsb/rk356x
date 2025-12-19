# ADR-0002: Debian Desktop Build System

**Status:** Accepted

**Date:** 2025-11-25

**Deciders:** @aaronsb

**Technical Story:** Commits `75b6878` through `807066f`

## Context

ADR-0001 selected Buildroot for its minimal footprint and embedded focus. This was the right call for a headless embedded device.

However, during hardware bring-up (Nov 14-25), requirements evolved:

1. **GPU acceleration needed** - The Mali Bifrost GPU requires userspace drivers that are complex to integrate in Buildroot
2. **Desktop environment required** - Target use case shifted toward interactive display applications
3. **Rapid iteration valued** - Buildroot's "rebuild for any package change" slowed experimentation
4. **Team familiarity** - Debian's apt-based workflow reduced friction during bring-up

The original Buildroot rationale (minimal size, fast boot, small attack surface) remains valid for production embedded deployments. But for desktop/GPU workloads with active development, Debian offers better trade-offs.

## Decision Drivers

- GPU driver integration complexity in Buildroot
- Need for desktop environment (display applications)
- Development velocity during hardware bring-up
- Team familiarity with Debian ecosystem
- Buildroot still available for minimal/headless builds

## Considered Options

### Option 1: Stay with Buildroot

**Description:** Continue Buildroot path, integrate GPU drivers manually.

**Pros:**
- Consistent with ADR-0001
- Minimal image size
- Fast boot

**Cons:**
- GPU driver integration is complex and fragile
- No package manager slows iteration
- Desktop environment in Buildroot is non-trivial
- Fighting the tool for our use case

### Option 2: Yocto/OpenEmbedded

**Description:** Migrate to Yocto for better package ecosystem.

**Pros:**
- Industry standard
- Better GPU/graphics layer support
- Professional tooling

**Cons:**
- Steep learning curve (weeks)
- Overkill for current team size
- Would further delay hardware bring-up

### Option 3: Debian with Docker builds (selected)

**Description:** Return to Debian (bookworm), use Docker for reproducible builds, keep Buildroot as legacy option.

**Pros:**
- Familiar apt workflow accelerates development
- GPU drivers available as packages
- Desktop environments well-supported
- Docker provides reproducibility
- ~45 minute builds (acceptable)
- Buildroot scripts preserved for future minimal builds

**Cons:**
- Larger image size (~1.5-2 GB vs 50-200 MB)
- Slower boot (acceptable for desktop use)
- More packages to maintain

## Decision

We adopt Debian 12 (bookworm) as the primary build system for desktop/GPU workloads.

Key implementation choices:
- **Docker-based builds** for reproducibility across host environments
- **debootstrap** for rootfs generation
- **Package profiles** (minimal/full) to manage image size
- **Buildroot preserved** in `scripts/legacy/` for future minimal builds

This supersedes ADR-0001 for the primary build path, while acknowledging Buildroot remains valid for headless embedded deployments.

## Consequences

### Positive

- GPU acceleration works out-of-box with Panfrost/Mesa packages
- Desktop environment (XFCE, later sway) integrates cleanly
- apt-get enables rapid package experimentation
- Docker ensures reproducible builds regardless of host
- Build time ~45 minutes is acceptable for iterative development
- Team productivity increased significantly

### Negative

- Image size increased from ~100 MB to ~1.5 GB
- Boot time increased (acceptable for desktop use case)
- More packages means larger attack surface (mitigated by standard Debian security updates)
- Two build systems to maintain (Debian primary, Buildroot legacy)

### Neutral

- Build scripts restructured (`build.sh` orchestrator, component scripts)
- Documentation updated to reflect Debian-first approach
- CI/CD workflows adapted for Debian builds

## Implementation Notes

The transition happened rapidly (Nov 25-26) driven by GPU bring-up needs:

1. `75b6878` - Initial Debian rootfs scripts
2. `e621c3f` - Docker containerization
3. `c461a83` - Interactive build orchestrator
4. `829d8e8` - Legacy Buildroot scripts moved to `scripts/legacy/`
5. `807066f` - Merge completing the transition

Build workflow:
```bash
./build.sh              # Interactive orchestrator
./build.sh --auto       # Non-interactive full build
./build.sh --clean      # Clean all artifacts
```

## References

- ADR-0001: Original Buildroot decision (now superseded)
- `scripts/legacy/` - Preserved Buildroot scripts
- Commit range: `75b6878..807066f`
