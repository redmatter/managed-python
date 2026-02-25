<p align="center">
  <img src="img/logo.png" alt="managed-python" width="200" />
</p>

# Managed Python

Bootstrap `uv` and a managed Python runtime to a configurable prefix. Provides a predictable Python environment for Claude Code customisation scripts and other tools.

## How it works

Installation is split into two phases:

| Phase | Script | Does |
|-------|--------|------|
| Bootstrap | `install.sh` / `install.ps1` | Downloads uv, creates venv |
| Configure | `setup.py` (stdlib only) | Writes env files, bin/ wrappers, shell profile |

The shell scripts are intentionally minimal — they exist only because downloading a binary and creating a venv require platform-specific shell syntax. Everything after that runs inside the freshly-created Python venv via `setup.py`, which is pure stdlib and cross-platform.

## Installation

Download the latest release ZIP from GitHub, extract it, and run the installer:

```bash
# Download and extract
curl -fsSL https://github.com/redmatter/managed-python/releases/latest/download/managed-python-<VERSION>.zip -o managed-python.zip
unzip managed-python.zip
```

```powershell
# Windows PowerShell
Invoke-WebRequest https://github.com/redmatter/managed-python/releases/latest/download/managed-python-<VERSION>.zip -OutFile managed-python.zip
Expand-Archive managed-python.zip
```

## Quick Start

**Linux / macOS:**

```bash
./install.sh \
  --prefix ~/.claude/redmatter/python \
  --min-python 3.10 \
  --uv-env REDMATTER_UV \
  --python-env REDMATTER_PYTHON

source ~/.claude/redmatter/python/env.sh
```

**Windows (PowerShell):**

```powershell
.\install.ps1 `
  -Prefix "$env:USERPROFILE\.claude\redmatter\python" `
  -MinPython "3.10" `
  -UvEnv "REDMATTER_UV" `
  -PythonEnv "REDMATTER_PYTHON"

. "$env:USERPROFILE\.claude\redmatter\python\env.ps1"
```

> [!NOTE]
> If your system blocks PowerShell scripts (`running scripts is disabled on this system`), use
> `install.bat` instead of `install.ps1`, and source the environment with `call` instead of dot-sourcing:
>
> ```bat
> install.bat -Prefix "%USERPROFILE%\.claude\redmatter\python" -MinPython "3.10" -UvEnv "REDMATTER_UV" -PythonEnv "REDMATTER_PYTHON"
> call "%USERPROFILE%\.claude\redmatter\python\env.bat"
> ```
>
> To remove the restriction permanently, run in an elevated PowerShell prompt:
> `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

**Scripted install (quiet mode):**

```bash
./install.sh \
  --prefix ~/.claude/redmatter/python \
  --min-python 3.10 \
  --uv-env REDMATTER_UV \
  --python-env REDMATTER_PYTHON \
  --quiet

source ~/.claude/redmatter/python/env.sh
"$REDMATTER_PYTHON" /path/to/script.py
```

## Options

| Flag | Required | Purpose |
|------|----------|---------|
| `--prefix PATH` | yes | Install location |
| `--min-python X.Y` | yes | Minimum Python version for venv |
| `--uv-env NAME` | yes | Env var name for the uv binary path |
| `--python-env NAME` | yes | Env var name for the python binary path |
| `--shell-profile` | no | Append `source <prefix>/env.sh` to shell rc |
| `--quiet` / `-q` | no | Suppress all output except warnings |

## Usage

```bash
# Run a stdlib script
"$REDMATTER_PYTHON" /path/to/script.py

# Run a script with dependencies (pyproject.toml in app dir)
"$REDMATTER_UV" run --project ~/.claude/my-app my-script.py

# Install a package into the shared venv (use sparingly)
"$REDMATTER_UV" pip install --python "$REDMATTER_PYTHON" some-package

# Fallback when managed-python may not be installed
PYTHON="${REDMATTER_PYTHON:-python3}"
exec "$PYTHON" script.py
```

## Layout After Install

```text
<prefix>/
  uv                          # uv binary
  bin/
    python -> ../venv/bin/python   # symlink (Linux/macOS)
    uv -> ../uv                    # symlink (Linux/macOS)
    python.cmd                     # wrapper (Windows)
    uv.cmd                         # wrapper (Windows)
  venv/
    bin/python                # Linux/macOS
    Scripts/python.exe        # Windows
  env.sh                      # exports env vars + conditional PATH (bash)
  env.ps1                     # exports env vars + conditional PATH (PowerShell)
  env.bat                     # exports env vars + conditional PATH (CMD / restricted PS)
  distro.toml                 # source version record + [install] options
```

## distro.toml — installed copy

The installed `distro.toml` at `<prefix>/distro.toml` records the options used during setup, making the install inspectable and replayable:

```toml
[distro]
version = "1.0.0"
uv_version = "0.10.6"

[install]
prefix       = "/home/user/.claude/redmatter/python"
min_python   = "3.10"
uv_env       = "REDMATTER_UV"
python_env   = "REDMATTER_PYTHON"
shell_profile = false
```

## Idempotency

Re-running `install.sh` with the same args is always safe:
- uv download skipped if pinned version already installed
- venv creation skipped if `venv/bin/python` already works
- All generated files (`env.sh`, `env.ps1`, `bin/`, `distro.toml`) are always regenerated (cheap, ensures correctness)

## Versioning

`distro.toml` `version` tracks the managed-python configuration itself:
- **Patch** (1.0.x) — no-op fixes
- **Minor** (1.x.0) — new flags, new generated files, non-breaking additions
- **Major** (x.0.0) — breaking layout change; delete prefix dir and reinstall
