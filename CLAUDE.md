# managed-python — AI Assistant Guide

Bootstrap `uv` and a managed Python runtime to a configurable prefix.

## Design Ethos

### Env vars are the contract, PATH is a convenience

`$REDMATTER_PYTHON` and `$REDMATTER_UV` (or whatever the caller names them) are always exported, unconditionally. Scripts reference these vars directly — they never rely on `python` or `uv` being on PATH. PATH is only modified in `env.sh` when it won't shadow an existing system `python`/`uv`. When both are already present, we print instructions for manual override and leave PATH alone.

### Non-destructive by default

Never replace what the user already has without telling them. If system `python` or `uv` is found, warn before shadowing. Never silently overwrite. The user's environment is theirs.

### Idempotency over fresh installs

Re-running `install.sh` with the same args must be safe. Skip uv download when the pinned version is already present. Skip venv creation when `venv/bin/python` works. Always regenerate `env.sh`, `env.ps1`, `bin/` wrappers, and `distro.toml` (cheap, ensures correctness). "Run it again" is the update path.

### Distro version tracks config, not Python or uv

`distro.toml` `version` reflects the managed-python configuration itself — install behaviour, layout, env var contract. It is bumped when:
- The minimum Python version changes
- The uv pin changes
- The install layout changes
- Major version = breaking change requiring a clean reinstall

### No runtime dependencies (beyond the shell)

`install.sh` uses only POSIX shell built-ins plus `curl` or `wget` (one of which is universally available). No Python, no pip, no homebrew, no build tools. The whole point is that we install Python — we cannot depend on it.

### Cross-platform parity

`install.sh` (bash) and `install.ps1` (PowerShell) expose identical flags and produce equivalent layouts. Windows uses `.cmd` wrappers instead of symlinks (symlinks require admin elevation). Both write `env.sh` and `env.ps1`.

### TUI: minimal output, one box for emphasis

Progress steps use plain prefixed lines (`==>`, `✓`, `ℹ`, `⚠`). No banners, no ASCII art at the top. A single `┌─ Install complete! ─┐` box appears at the end to signal completion. Boxes exist to grab attention at the right moment — not to decorate every step.

### Pinned versions, explicit upgrades

`uv_version` in `distro.toml` is always a specific release, never a range or `latest`. Upgrading means editing `distro.toml` and re-running. This makes installs reproducible and avoids surprises when uv releases breaking changes.

## Key Files

| File | Purpose |
|------|---------|
| `distro.toml` | Source of truth for pinned versions |
| `install.sh` | Linux/macOS bootstrap |
| `install.ps1` | Windows PowerShell bootstrap |

## Layout After Install

```
<prefix>/
  uv                         # uv binary (Linux/macOS)
  uv.exe                     # uv binary (Windows)
  bin/
    python -> ../venv/bin/python   # symlink (Linux/macOS)
    uv -> ../uv                    # symlink (Linux/macOS)
    python.cmd                     # wrapper (Windows)
    uv.cmd                         # wrapper (Windows)
  venv/
    bin/python               # Linux/macOS
    Scripts/python.exe       # Windows
  env.sh                     # exports env vars + conditional PATH (bash)
  env.ps1                    # exports env vars + conditional PATH (PowerShell)
  distro.toml                # copy of source distro.toml (version record)
```

## Common Patterns

```bash
# Simple stdlib script
"$REDMATTER_PYTHON" /path/to/script.py

# Script with deps (pyproject.toml in app dir)
"$REDMATTER_UV" run --project ~/.claude/my-app my-script.py

# Install a package into the shared venv (use sparingly)
"$REDMATTER_UV" pip install --python "$REDMATTER_PYTHON" some-package

# Fallback when managed-python may not be installed
PYTHON="${REDMATTER_PYTHON:-python3}"
exec "$PYTHON" script.py
```

## Versioning

- Patch (1.0.x): no-op fixes, documentation
- Minor (1.x.0): new flags, new generated files, non-breaking layout additions
- Major (x.0.0): breaking layout change — delete prefix and reinstall
