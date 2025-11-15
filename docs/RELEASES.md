# Release Management

## Version Scheme

This project uses [Semantic Versioning](https://semver.org/):

- **MAJOR** version: Incompatible API changes or major architectural changes
- **MINOR** version: New features in a backwards-compatible manner
- **PATCH** version: Backwards-compatible bug fixes

## Creating a Release

### Using the Release Script

The easiest way to create a release is using the `scripts/release.sh` script:

```bash
# Patch release (0.1.0 -> 0.1.1)
./scripts/release.sh patch

# Minor release (0.1.1 -> 0.2.0)
./scripts/release.sh minor

# Major release (0.2.0 -> 1.0.0)
./scripts/release.sh major
```

The script will:
1. Show current and new version
2. Ask for confirmation
3. Update the VERSION file
4. Commit the version bump
5. Create and push a git tag
6. Trigger GitHub Actions to build and create the release

### Manual Release Process

If you prefer to create releases manually:

```bash
# Update VERSION file
echo "0.2.0" > VERSION

# Commit version bump
git add VERSION
git commit -m "Bump version to 0.2.0"

# Create and push tag
git tag -a v0.2.0 -m "Release v0.2.0"
git push && git push --tags
```

## Automated Build Process

When a tag is pushed:

1. **GitHub Actions automatically triggers** a full build (config-only is bypassed for tags)
2. **Buildroot compiles** the complete system image (~60 minutes)
3. **Artifacts are packaged**:
   - `rk356x-vX.X.X-rk3568_jvl.tar.gz` - Complete image archive
   - `rootfs.tar.gz` - Root filesystem only
   - `Image` - Linux kernel binary
   - `*.dtb` - Device tree blobs
4. **GitHub Release is created** with all artifacts attached
5. **Release notes are auto-generated** from commits since last tag

## Release Artifacts

Each release includes:

### Complete Archive (`rk356x-*.tar.gz`)
Contains all components needed for deployment:
- Root filesystem
- Kernel image
- Device tree blobs

### Individual Components
Available separately for advanced users:
- **rootfs.tar.gz**: Root filesystem (can be extracted to existing partition)
- **Image**: Linux kernel binary (can be used with existing device tree)
- **\*.dtb**: Device tree blobs for different board variants

## Using Releases

### Download Latest Release

Visit the [Releases page](https://github.com/aaronsb/rk356x/releases) and download the artifacts for your board.

### Flash Complete Image

```bash
# Extract the complete archive
tar xzf rk356x-v0.1.0-rk3568_jvl.tar.gz

# Flash to SD card (replace /dev/sdX with your device)
sudo dd if=sdcard.img of=/dev/sdX bs=4M status=progress conv=fsync
```

### Extract Root Filesystem Only

```bash
# Extract rootfs to existing partition
sudo tar xzf rootfs.tar.gz -C /mnt/rootfs
```

## Development Workflow

### Pre-Release Testing

Before creating a release, test the build locally:

```bash
cd buildroot
BR2_EXTERNAL=../external/custom make rk3568_custom_defconfig
make -j$(nproc)
```

### Release Checklist

- [ ] All features tested and working
- [ ] Documentation updated
- [ ] CHANGELOG.md updated (if exists)
- [ ] Version number follows semantic versioning
- [ ] No uncommitted changes
- [ ] All tests pass locally

## Troubleshooting

### Release Build Failed

If the GitHub Actions build fails:
1. Check the [Actions tab](https://github.com/aaronsb/rk356x/actions)
2. Review the build logs
3. Fix any issues
4. Delete the failed tag: `git tag -d v0.1.0 && git push --delete origin v0.1.0`
5. Create a new patch release with fixes

### Missing Artifacts

If artifacts are missing from the release:
- Ensure the build completed successfully
- Check that all expected files exist in `buildroot/output/images/`
- Review the "Prepare release artifacts" step in the workflow logs

## Future Enhancements

Planned improvements to the release system:

- [ ] Automated changelog generation from commits
- [ ] Pre-release/beta releases for testing
- [ ] Checksum generation for all artifacts
- [ ] Flash tool integration (e.g., `rkdeveloptool`)
- [ ] Support for multiple board variants in single release
