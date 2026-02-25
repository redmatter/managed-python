# managed-python

Bootstrap `uv` and a managed Python runtime to a configurable prefix. Provides a predictable Python environment for Claude Code customisation scripts and other tools.

## Overview

`managed-python` installs:
- A pinned version of [`uv`](https://github.com/astral-sh/uv) to `<prefix>/uv`
- A Python venv (via uv) to `<prefix>/venv/`
- Convenience symlinks at `<prefix>/bin/python` and `<prefix>/bin/uv`
- An `env.sh` / `env.ps1` that exports `$<UV_ENV>` and `$<PYTHON_ENV>` env vars

## Quick Start

```bash
./install.sh \
  --prefix ~/.claude/redmatter/python \
  --min-python 3.10 \
  --uv-env REDMATTER_UV \
  --python-env REDMATTER_PYTHON

source ~/.claude/redmatter/python/env.sh
```

## Usage

```bash
# Run a stdlib script
"$REDMATTER_PYTHON" /path/to/script.py

# Run a script with deps (pyproject.toml in app dir)
"$REDMATTER_UV" run --project ~/.claude/my-app my-script.py

# Install a package into the shared venv
"$REDMATTER_UV" pip install --python "$REDMATTER_PYTHON" some-package
```

## install.sh Options

| Flag | Required | Purpose |
|------|----------|---------|
| `--prefix PATH` | yes | Install location |
| `--min-python X.Y` | yes | Minimum Python version for venv |
| `--uv-env NAME` | yes | Env var name for uv binary path |
| `--python-env NAME` | yes | Env var name for python binary path |
| `--shell-profile` | no | Append `source <prefix>/env.sh` to shell rc |

## Versioning

`distro.toml` pins the uv version and tracks the distro version. Re-running `install.sh` is idempotent within the same major version.

## Layout After Install

```
<prefix>/
  uv                        # uv binary
  bin/
    python -> ../venv/bin/python
    uv -> ../uv
  venv/
    bin/python              # Linux/macOS
    Scripts/python.exe      # Windows
  env.sh                    # exports env vars + conditional PATH
  env.ps1                   # PowerShell equivalent
  distro.toml               # version record
```
