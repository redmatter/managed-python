# managed-python — AI Assistant Guide

Bootstrap `uv` and a managed Python runtime to a configurable prefix.

## Architecture

Installation is split into two phases:

```text
install.sh / install.ps1   →   setup.py   →   configured prefix
  (bootstrap: uv + venv)       (configure: everything else)
```

**Bootstrap scripts** (`install.sh`, `install.ps1`) are minimal — they exist only because downloading a binary and creating a venv require platform-specific shell syntax before Python is available. Once the venv exists, control passes immediately to `setup.py`.

**`setup.py`** runs inside the freshly-created venv and handles all logic that would otherwise be duplicated across bash and PowerShell: bin/ wrappers, env.sh, env.ps1, distro.toml copy, shell profile update. It is pure stdlib with no external dependencies.

## Design Ethos

### setup.py is stdlib-only, always

`setup.py` must never import anything outside the Python standard library. No `pip install`, no `pyproject.toml` for setup.py itself. It runs inside a freshly-created venv that has no packages installed. Any helper logic that might seem to warrant a library (TOML parsing, path manipulation, HTTP) must be implemented with stdlib primitives.

This is non-negotiable. The moment setup.py gains a dependency, bootstrap becomes circular.

### Shell scripts do the minimum necessary

`install.sh` and `install.ps1` exist for exactly two reasons: (1) downloading a binary requires curl/wget or Invoke-WebRequest, and (2) creating a venv requires the uv binary that was just downloaded. Nothing else belongs in the shell scripts. No PATH logic, no env file generation, no output formatting beyond simple progress lines.

### Env vars are the contract, PATH is a convenience

`$REDMATTER_PYTHON` and `$REDMATTER_UV` (or whatever names the caller chooses) are always exported, unconditionally. Scripts reference these vars directly — they never rely on `python` or `uv` being on PATH. PATH is only modified in `env.sh`/`env.ps1` when it won't shadow an existing system `python`/`uv`.

### The installed distro.toml is a record of intent

The source `distro.toml` pins versions. The installed copy at `<prefix>/distro.toml` adds an `[install]` section recording the exact options used (`prefix`, `min_python`, `uv_env`, `python_env`, `shell_profile`). This makes the install inspectable and replayable without remembering what flags were passed.

### Non-destructive by default

Never replace what the user already has without telling them. If system `python` or `uv` is found on PATH, warn before shadowing. Never silently overwrite.

### Idempotency over fresh installs

Re-running `install.sh` with the same args is always safe. uv and venv creation are skipped when already current. All generated files are always regenerated (cheap, ensures correctness).

### Distro version tracks config, not Python or uv

`distro.toml` `version` reflects the managed-python configuration itself — install behaviour, layout, env var contract. Patch = no-op. Minor = new non-breaking features. Major = breaking layout change requiring clean reinstall.

### TUI: minimal output, one box for emphasis

Bootstrap phase: plain `→` / `✓` prefix lines from the shell script.
Configure phase: `==>` step headers + `✓` / `ℹ` / `⚠` prefix lines from setup.py.
One `┌─ Install complete! ─┐` box appears at the end to signal completion. No decorative banners.

## Key Files

| File | Purpose |
|------|---------|
| `distro.toml` | Source of truth for pinned uv version and distro version |
| `install.sh` | Linux/macOS bootstrap (uv download + venv creation only) |
| `install.ps1` | Windows PowerShell bootstrap (uv download + venv creation only) |
| `setup.py` | Cross-platform configuration — stdlib only, no deps |

## What Goes Where

| Concern | Script |
|---------|--------|
| Download uv binary | `install.sh` / `install.ps1` |
| Create Python venv | `install.sh` / `install.ps1` |
| Write `env.sh` / `env.ps1` | `setup.py` |
| Create `bin/` wrappers / symlinks | `setup.py` |
| PATH detection logic | `setup.py` |
| Shell profile update | `setup.py` |
| Output: step headers, completion box | `setup.py` |
| Record install options | `setup.py` → installed `distro.toml` |

## Common Patterns

```bash
# Simple stdlib script
"$REDMATTER_PYTHON" /path/to/script.py

# Script with dependencies (pyproject.toml in app dir)
"$REDMATTER_UV" run --project ~/.claude/my-app my-script.py

# Install a package into the shared venv (use sparingly)
"$REDMATTER_UV" pip install --python "$REDMATTER_PYTHON" some-package

# Fallback when managed-python may not be installed
PYTHON="${REDMATTER_PYTHON:-python3}"
exec "$PYTHON" script.py
```

## Versioning

- Patch (1.0.x): no-op fixes, documentation
- Minor (1.x.0): new flags, new generated files, non-breaking additions
- Major (x.0.0): breaking layout change — delete prefix and reinstall
