# Releasing

## Version guidelines

`distro.toml` holds three pins, and they move on separate schedules:

| Pin | Tracks | Bumped by |
| ----- | -------- | ----------- |
| `version` | The managed-python configuration itself, not Python, uv, or PyYAML | `release.py` (`--patch` / `--minor` / `--major`) |
| `uv_version` | The pinned uv release (plus its `[uv_checksums]` entries) | `release.py --uv-version X.Y.Z` |
| `pyyaml_version` | The pinned bootstrap PyYAML wheel | A direct edit - `release.py` does not manage it (see [CONTRIBUTING.md](CONTRIBUTING.md)) |

| Bump | When |
| ------ | ------ |
| **patch** (1.0.x) | No-op fixes, documentation |
| **minor** (1.x.0) | New flags, new generated files, non-breaking additions |
| **major** (x.0.0) | Breaking layout change - users must delete prefix and reinstall |

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

`release.py` manages two of the three pins: `version` and `uv_version`. The third, `pyyaml_version`,
has no flag (`--pyyaml-version` deliberately does not exist) and is bumped by a direct edit to
`distro.toml` in whichever commit needs the new wheel. See the note in
[CONTRIBUTING.md](CONTRIBUTING.md) for why it stays manual.

## Manual steps

1. Run `release.py` with `--tag` (or tag manually after committing `distro.toml`)
2. Push the commit and tag:

   ```bash
   git push && git push origin vX.Y.Z
   ```

3. The [release workflow](.github/workflows/release.yml) picks up the tag, verifies the tag matches `distro.toml`, builds the ZIP, and publishes the GitHub release automatically.

## CI version check

The release workflow fails if the git tag does not match `version` in `distro.toml`. This prevents publishing a release with a mismatched version.
