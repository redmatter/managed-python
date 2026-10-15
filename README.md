<p align="center">
  <img src="img/logo.png" alt="managed-python" width="200" />
</p>

# Managed Python

Bootstrap `uv` and a managed Python runtime to a configurable prefix. Provides a predictable, isolated Python environment for scripts and tools across Linux, macOS, and Windows.

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
  --prefix ~/.local/redmatter/python \
  --python 3.10 \
  --env-prefix REDMATTER

source ~/.local/redmatter/python/env.sh
```

**Windows (PowerShell):**

```powershell
.\install.ps1 `
  -Prefix "$env:USERPROFILE\.local\redmatter\python" `
  -Python "3.10" `
  -EnvPrefix "REDMATTER"

. "$env:USERPROFILE\.local\redmatter\python\env.ps1"
```

> [!NOTE]
> If your system blocks PowerShell scripts (`running scripts is disabled on this system`), use
> `install.bat` to install, then load the environment using one of the options below depending on your shell.
>
> **PowerShell** — evaluate `env.ps1` as a string (bypasses script execution policy):
>
> ```powershell
> install.bat -Prefix "$env:USERPROFILE\.local\redmatter\python" -Python "3.10" -EnvPrefix "REDMATTER"
> Invoke-Expression (Get-Content "$env:USERPROFILE\.local\redmatter\python\env.ps1" -Raw)
> ```
>
> **CMD** — use `call` to load `env.bat` into the current session:
>
> ```bat
> install.bat -Prefix "%USERPROFILE%\.local\redmatter\python" -Python "3.10" -EnvPrefix "REDMATTER"
> call "%USERPROFILE%\.local\redmatter\python\env.bat"
> ```
>
> To remove the restriction permanently, run in an elevated PowerShell prompt:
> `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

**Scripted install (quiet mode):**

```bash
./install.sh \
  --prefix ~/.local/redmatter/python \
  --python 3.10 \
  --env-prefix REDMATTER \
  --quiet

source ~/.local/redmatter/python/env.sh
"$REDMATTER_PYTHON" /path/to/script.py
```

## Options

| Flag | Required | Purpose |
| ------ | ---------- | --------- |
| `--prefix PATH` | yes | Install location |
| `--python X.Y` | yes | Python version for venv. Default mode: prefer matching system Python, fall back to uv-managed. Isolated mode: always uv-managed. |
| `--env-prefix NAME` | yes* | Derives `NAME_UV`, `NAME_UVX`, and `NAME_PYTHON` — preferred over the three flags below |
| `--uv-env NAME` | yes* | Env var name for the uv binary path |
| `--uvx-env NAME` | yes* | Env var name for the uvx binary path |
| `--python-env NAME` | yes* | Env var name for the python binary path |
| `--cooldown DURATION` | no | Package cooldown, default `P1D`. Ignores distributions uploaded within the window. `P0D` disables. See [Package cooldown](#package-cooldown) |
| `--isolated` | no | Force uv-managed Python (ignores system Python); always adds `bin/` to PATH |
| `--shell-profile` | no | Append `source <prefix>/env.sh` to shell rc |
| `--quiet` / `-q` | no | Suppress all output except warnings |

\* Use either `--env-prefix` **or** all three of `--uv-env` / `--uvx-env` / `--python-env` — they are mutually exclusive.

> [!NOTE]
> **Choosing a mode:** Use the default on developer machines where a system Python already exists. Use `--isolated` in CI, containers, or shared servers where you need a fully reproducible environment independent of whatever Python is (or isn't) installed on the host.

## Package cooldown

Every install ships a **1-day package cooldown** by default: the generated env files export `UV_EXCLUDE_NEWER="P1D"`, so uv ignores any distribution uploaded in the last 24 hours.

This is deliberate, and it follows the guidance in the AWS Security Blog post [Secure your npm and pip package updates in Amazon Linux](https://aws.amazon.com/blogs/security/secure-your-npm-and-pip-package-updates-in-amazon-linux/). Modern supply-chain attacks publish a malicious version and rely on it being pulled into builds within minutes, while detection and yanking typically happen within hours. Waiting a day costs you almost nothing and keeps you out of the blast radius - patience really is a virtue here.

`--cooldown` accepts anything uv's `--exclude-newer` accepts: an ISO 8601 duration (`P1D`, `PT12H`, `P2W`), a friendly duration (`3 days`), a date (`2026-01-01`), or an RFC 3339 timestamp. `P0D` turns the cooldown off.

```bash
./install.sh --prefix ~/.local/redmatter/python --python 3.10 \
  --env-prefix REDMATTER --cooldown "3 days"
```

### Overriding for an urgent patch

The cooldown is a default, not a cage. A command-line flag beats the env var:

```bash
# Bypass the cooldown entirely for one command
"$REDMATTER_UV" pip install --exclude-newer P0D --python "$REDMATTER_PYTHON" some-package

# Or bypass it for one package only, keeping the cooldown for everything else
"$REDMATTER_UV" pip install --exclude-newer-package some-package=P0D \
  --python "$REDMATTER_PYTHON" some-package
```

### What it does and does not cover

| Scope | Covered? |
| ------ | ---------- |
| `uv pip install`, `uv add`, `uv lock`, `uv sync` resolution | Yes |
| `uvx` / `uv tool install` resolution | Yes |
| Existing `uv.lock` installs | No - `uv lock` records the resolved `exclude-newer` timestamp (and its `exclude-newer-span`) into the lockfile, and `uv sync` honours that until you pass `--upgrade` or `--refresh`. This mirrors the `npm ci` and pinned-`requirements.txt` caveat in the AWS post |
| Managed Python interpreter downloads (`uv python install`) | No - `exclude-newer` applies to package resolution only |
| A `pip` inside your own project venvs | No - `pip` has its own `global.uploaded-prior-to` setting. The managed venv contains no `pip` |

> [!IMPORTANT]
> `UV_EXCLUDE_NEWER` is uv's own environment variable, so unlike `REDMATTER_UV` it cannot be namespaced. Sourcing `env.sh` therefore applies the cooldown to **any** `uv` on your `PATH`, not just the managed one. To get a completely untouched uv in the shell you are already in, run `unset UV_EXCLUDE_NEWER` — reinstalling with `--cooldown P0D` only comments the assignment out, which affects new shells and future sources, not the current one.

## Interpreter preference

Every install sets `UV_PYTHON_PREFERENCE="managed"` in the generated env files, but only when the variable is unset or empty. If you already export a value, it is left alone.

`managed` makes uv prefer an interpreter it manages itself over one it finds on `PATH`. It does not reject an existing project environment just because a system Python raised it - no eviction notice. Normal checks still apply, so a `.venv` that does not match the project's Python version is still replaced.

`managed` is already uv's own default, so in a project with no interpreter configuration this setting changes nothing. Its effect is to override a configuration that asks for a system interpreter, such as `python-preference = "system"` in a project's `pyproject.toml`. The original fault appeared in exactly that shape, which is the case this guard is for.

There is one limit to know about. `managed` is a preference, not a wall, and it is not a health check on the interpreter it picks. When no installed managed interpreter satisfies the request, uv falls back to a Python found on `PATH`. That is not limited to unusual versions: on a machine with no managed 3.14 installed, a request for 3.14 can resolve to a system Python. Measured on 2026-10-14 against uv 0.10.12: a request for Python 3.15, for which no managed interpreter was installed, resolved to `/opt/homebrew/opt/python@3.15/bin/python3.15`. So a broken interpreter on `PATH` remains reachable whenever no installed managed interpreter satisfies the request, and an existing `.venv` built on one is still used.

This setting is an extra guard, not the fix. The direct fix for the original fault was removing the dead symlinks in `~/.local/bin` that pointed at a broken interpreter.

It is a preference, not a pin, and the difference matters:

- A `UV_PYTHON` pin would name the exact interpreter that `uv pip install` writes into. It would also override normal interpreter selection, including `.python-version`, and where the project sets `requires-python`, uv checks the pinned interpreter against it and fails on a conflict. `UV_PYTHON_PREFERENCE` does neither. It only narrows which interpreter uv reaches for, so the project keeps control of its own version.

> [!IMPORTANT]
> `UV_PYTHON_PREFERENCE` is uv's own environment variable, so unlike `REDMATTER_UV` it cannot be namespaced. Sourcing `env.sh` therefore applies the preference to **any** `uv` on your `PATH`, not just the managed one. A shell-wide value also outranks a repository's own `[tool.uv] python-preference` setting. Override it for one command with `UV_PYTHON_PREFERENCE=system uv ...`, or clear it in the shell you are already in with `unset UV_PYTHON_PREFERENCE`. The generated files only set the variable when it is unset or empty, so a value you export yourself always wins.

## Usage

```bash
# Run a stdlib script
"$REDMATTER_PYTHON" /path/to/script.py

# Run a script with dependencies (pyproject.toml in app dir)
"$REDMATTER_UV" run --project /path/to/app my-script.py

# Run a tool without installing it
"$REDMATTER_UVX" ruff --version

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
  uvx                         # uvx binary
  bin/
    python -> ../venv/bin/python   # symlink (Linux/macOS)
    uv -> ../uv                    # symlink (Linux/macOS)
    uvx -> ../uvx                  # symlink (Linux/macOS)
    python.cmd                     # wrapper (Windows)
    uv.cmd                         # wrapper (Windows)
    uvx.cmd                        # wrapper (Windows)
  venv/
    bin/python                # Linux/macOS
    Scripts/python.exe        # Windows
  env.sh                      # exports env vars + cooldown + conditional PATH (bash)
  env.ps1                     # exports env vars + cooldown + conditional PATH (PowerShell)
  env.bat                     # exports env vars + cooldown + conditional PATH (CMD / restricted PS)
  distro.toml                 # source version record + [install] options
```

## distro.toml — installed copy

The installed `distro.toml` at `<prefix>/distro.toml` records the options used during setup, making the install inspectable and replayable:

```toml
[distro]
version = "1.0.0"
uv_version = "0.10.6"

[install]
prefix       = "/home/user/.local/redmatter/python"
python       = "3.10"
uv_env       = "REDMATTER_UV"
uvx_env      = "REDMATTER_UVX"
python_env   = "REDMATTER_PYTHON"
cooldown     = "P1D"
shell_profile = false
isolated      = false
```

## Idempotency

Re-running `install.sh` with the same args is always safe:

- uv download skipped only if **both** `uv` and `uvx` are present and `uv` matches the pinned version — a missing `uvx` re-downloads the pair, since they ship in one archive
- venv creation skipped if `venv/bin/python` already works
- All generated files (`env.sh`, `env.ps1`, `bin/`, `distro.toml`) are always regenerated (cheap, ensures correctness)

## Versioning

`distro.toml` `version` tracks the managed-python configuration itself:

- **Patch** (1.0.x) — no-op fixes
- **Minor** (1.x.0) — new flags, new generated files, non-breaking additions
- **Major** (x.0.0) — breaking layout change; delete prefix dir and reinstall
