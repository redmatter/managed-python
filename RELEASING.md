# Releasing

## Version guidelines

`distro.toml` `version` tracks the managed-python configuration itself — not Python or uv.

| Bump | When |
|------|------|
| **patch** (1.0.x) | No-op fixes, documentation |
| **minor** (1.x.0) | New flags, new generated files, non-breaking additions |
| **major** (x.0.0) | Breaking layout change — users must delete prefix and reinstall |

## Release script

`release.py` updates `distro.toml` and optionally commits + tags.

```bash
# Bump distro version only
python release.py --patch
python release.py --minor
python release.py --major

# Update pinned uv version only
python release.py --uv-version 0.11.0

# Combine: bump minor and update uv
python release.py --minor --uv-version 0.11.0

# Bump, commit, and tag in one step
python release.py --patch --tag

# Non-interactive (CI / scripted)
python release.py --patch --tag --yes
```

## Manual steps

1. Run `release.py` with `--tag` (or tag manually after committing `distro.toml`)
2. Push the commit and tag:
   ```bash
   git push && git push origin vX.Y.Z
   ```
3. The [release workflow](.github/workflows/release.yml) picks up the tag, verifies the tag matches `distro.toml`, builds the ZIP, and publishes the GitHub release automatically.

## CI version check

The release workflow fails if the git tag does not match `version` in `distro.toml`. This prevents publishing a release with a mismatched version.
