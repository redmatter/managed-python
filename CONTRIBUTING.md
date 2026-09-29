# Contributing to managed-python

## Architecture

Installation is split into two phases:

```text
install.sh / install.ps1   →   setup.py   →   configured prefix
  (bootstrap: uv + venv + pinned pyyaml)   (configure: everything else)
```

**Bootstrap scripts** (`install.sh`, `install.ps1`) are minimal — they exist because downloading a
binary, creating a venv, and installing the one pinned bootstrap package require platform-specific
shell syntax before Python is available. Once the venv exists, control passes immediately to
`setup.py`.

**`setup.py`** runs inside the freshly-created venv and handles all logic that would otherwise be
duplicated across bash and PowerShell: bin/ wrappers, env.sh, env.ps1, distro.toml copy, shell
profile update. It is pure stdlib with no external dependencies.

## What Goes Where

| Concern | Script |
| --------- | -------- |
| Download uv binary | `install.sh` / `install.ps1` |
| Create Python venv | `install.sh` / `install.ps1` |
| Install pinned `pyyaml` into the venv | `install.sh` / `install.ps1` |
| Write `env.sh` / `env.ps1` / `env.bat` | `setup.py` |
| Create `bin/` wrappers / symlinks | `setup.py` |
| PATH detection logic | `setup.py` |
| Shell profile update | `setup.py` |
| Output: step headers, completion box | `setup.py` |
| Record install options | `setup.py` → installed `distro.toml` |

## Design Principles

### setup.py is stdlib-only, always

`setup.py` must never import anything outside the Python standard library. It runs inside a
freshly-created venv whose only non-stdlib package is the pinned `pyyaml`, which it does not use.
Any helper logic that might seem to warrant a library (TOML parsing, path manipulation, HTTP) must
be implemented with stdlib primitives.

The moment `setup.py` gains a dependency, bootstrap becomes circular.

### Shell scripts do the minimum necessary

`install.sh` and `install.ps1` exist for three reasons: (1) downloading a binary requires curl/wget
or Invoke-WebRequest, (2) creating a venv requires the uv binary that was just downloaded, and
(3) installing the one pinned bootstrap package (`pyyaml`) must happen after the venv exists but
before `setup.py` hands over. No PATH logic, no env file generation, and no output formatting beyond
simple progress lines belongs in the shell scripts.

The bootstrap package set stays deliberately tiny: an exact pin to an immutable release is the
control for that dependency, so it needs no resolution policy and no cooldown. Anything more than a
single pinned package starts to look like configuration, which is `setup.py`'s job.

### Env vars are the contract, PATH is a convenience

The env var names passed via `--uv-env` and `--python-env` are always exported unconditionally.
Scripts should reference these vars directly and never rely on `python` or `uv` being on PATH. PATH
is only modified in `env.sh`/`env.ps1` when it won't shadow an existing system `python`/`uv`.

### Non-destructive by default

Never replace what the user already has without telling them. If system `python` or `uv` is found
on PATH, warn before shadowing. Never silently overwrite.

### Idempotency

Re-running the installer with the same args is always safe. uv and venv creation are skipped when
already current. All generated files are always regenerated (cheap, ensures correctness).

## Versioning

`distro.toml` `version` tracks the managed-python configuration itself — not Python or uv versions.

- **Patch** (x.y.Z) — no-op fixes, documentation
- **Minor** (x.Y.0) — new flags, new generated files, non-breaking additions
- **Major** (X.0.0) — breaking layout change; users must delete the prefix and reinstall

To cut a release:

```bash
python release.py --patch   # or --minor / --major
python release.py --uv-version X.Y.Z   # also updates pinned checksums
```

Add `--tag` to commit `distro.toml` and create a git tag in one step.

`pyyaml_version` is the third pin in `distro.toml`. `release.py` does not manage it, so bump it
with a direct edit in whichever commit needs the new version - there is no `--pyyaml-version` flag.

## Reporting Security Issues

See [SECURITY.md](SECURITY.md).
