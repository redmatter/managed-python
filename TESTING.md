# Testing Guide

Manual tests to run before releasing. Cover both platforms and both install modes.

## Linux / macOS

Run from the repository root.

### Setup

```bash
rm -rf /tmp/mp-test
```

### Test 1 — Non-isolated (system Python preferred)

```bash
./install.sh --prefix /tmp/mp-test --python 3.10 \
  --uv-env TEST_UV --uvx-env TEST_UVX --python-env TEST_PYTHON
```

**Expect:**

- uv downloaded (or skipped if already current)
- venv created using system Python if a matching version exists, otherwise uv-managed
- `distro.toml` contains `isolated = false` and `uvx_env = "TEST_UVX"`
- `env.sh` contains `export TEST_UVX=...` and `export PATH=...` (system python found → shadow warning; no system python → silently added)

```bash
grep -A8 '^\[install\]' /tmp/mp-test/distro.toml
cat /tmp/mp-test/env.sh
```

### Test 2 — Isolated (uv-managed Python, always)

```bash
rm -rf /tmp/mp-test
./install.sh --prefix /tmp/mp-test --python 3.10 \
  --uv-env TEST_UV --uvx-env TEST_UVX --python-env TEST_PYTHON --isolated
```

**Expect:**

- uv downloads a managed Python regardless of what's on the system
- `distro.toml` contains `isolated = true`
- `env.sh` always contains `export PATH=...` with note `--isolated: always adding bin/ to PATH`
- `venv/bin/python` is a uv-managed build (not `/usr/bin/python*`)

```bash
grep -A8 '^\[install\]' /tmp/mp-test/distro.toml
cat /tmp/mp-test/env.sh
/tmp/mp-test/venv/bin/python --version
```

### Test 3 — Idempotency

```bash
./install.sh --prefix /tmp/mp-test --python 3.10 \
  --uv-env TEST_UV --uvx-env TEST_UVX --python-env TEST_PYTHON --isolated
```

**Expect:**

- `✓ uv X.Y.Z` (skipped, already current)
- `✓ venv already exists` (skipped)
- env files regenerated cleanly

### Test 4 — Old flag rejected

```bash
./install.sh --prefix /tmp/mp-test --min-python 3.10 \
  --uv-env TEST_UV --uvx-env TEST_UVX --python-env TEST_PYTHON
```

**Expect:** exits with `ERROR: --python is required`

### Test 5 — Package cooldown (default)

```bash
rm -rf /tmp/mp-test
./install.sh --prefix /tmp/mp-test --python 3.10 --env-prefix TEST
grep UV_EXCLUDE_NEWER /tmp/mp-test/env.sh /tmp/mp-test/env.ps1
grep cooldown /tmp/mp-test/distro.toml
```

**Expect:**

- Install output shows `✓ UV_EXCLUDE_NEWER=P1D`
- `env.sh` contains `export UV_EXCLUDE_NEWER="P1D"`, `env.ps1` contains `$env:UV_EXCLUDE_NEWER = "P1D"`
- `distro.toml` `[install]` contains `cooldown = "P1D"`

### Test 6 — Cooldown actually bites

Uses a deliberately long window so the effect is unmistakable.

```bash
rm -rf /tmp/mp-test
./install.sh --prefix /tmp/mp-test --python 3.10 --env-prefix TEST --cooldown P365D -q
source /tmp/mp-test/env.sh
"$TEST_UV" pip install --dry-run --python "$TEST_PYTHON" requests | grep '+ requests'
"$TEST_UV" pip install --dry-run --exclude-newer P0D --python "$TEST_PYTHON" requests | grep '+ requests'
```

**Expect:** the first command resolves a visibly older `requests` than the second — proving both the
cooldown and the command-line bypass work.

### Test 7 — Cooldown disabled

```bash
rm -rf /tmp/mp-test
./install.sh --prefix /tmp/mp-test --python 3.10 --env-prefix TEST --cooldown P0D
```

**Expect:**

- Install output warns `⚠ disabled (--cooldown P0D)`
- `env.sh` contains the `UV_EXCLUDE_NEWER` line **commented out** — sourcing it sets nothing
- `distro.toml` contains `cooldown = "P0D"`

Repeat with the other zero-length spellings — `PT0H`, `P0W`, `0 days` — and expect the **same**
disabled treatment each time. A zero window is a zero window however it is written, and the
installer must never claim a cooldown it does not have.

### Test 8 — Invalid cooldown rejected

The value is validated by running it past uv itself (offline), so uv's own error is surfaced.

```bash
./install.sh --prefix /tmp/mp-test --python 3.10 --env-prefix TEST --cooldown yesterday
```

**Expect:** exits `1` with `ERROR: --cooldown 'yesterday' was rejected by uv:` followed by uv's
own message, and **no** `env.sh` / `env.ps1` / `distro.toml` written to the prefix.

Values that MUST be rejected: `yesterday`, `1 fortnight`, `P`, `2026-01-01T:`, `2026-01-01 ::::`

Values that MUST be accepted: `P1D`, `PT12H`, `P2W`, `P1DT2H`, `3 days`, `2026-01-01`,
`2026-01-01T00:00:00Z`

### Test 9 — Missing `uvx` forces a re-download

Guards against the bug in [#9](https://github.com/redmatter/managed-python/issues/9): the skip
condition used to check `uv`'s version only, so a prefix predating `uvx` could keep a broken
`bin/uvx` forever.

```bash
./install.sh --prefix /tmp/mp-test --python 3.10 --env-prefix TEST --isolated
rm -f /tmp/mp-test/uvx /tmp/mp-test/bin/uvx
./install.sh --prefix /tmp/mp-test --python 3.10 --env-prefix TEST --isolated
source /tmp/mp-test/env.sh && "$TEST_UVX" --version
```

**Expect:** the second install prints `→ Downloading uv X.Y.Z` (not `✓ uv X.Y.Z`), keeps
`✓ venv already exists`, and `$TEST_UVX --version` prints a version rather than
`No such file or directory`.

Then re-run Test 3 — a **complete** prefix must still print `✓ uv X.Y.Z` and skip the download.

### Test 10 — setup.py refuses to wrap a missing binary

`setup.py` will not create a wrapper pointing at thin air, even when run on its own.

```bash
mv /tmp/mp-test/uvx /tmp/uvx.bak
/tmp/mp-test/venv/bin/python setup.py --prefix /tmp/mp-test --python 3.10 --env-prefix TEST --isolated
echo "exit=$?"
mv /tmp/uvx.bak /tmp/mp-test/uvx
```

**Expect:** exits `1` with `ERROR: bootstrap incomplete - these are missing from the prefix:`
naming `uvx`, before any `==>` step header is printed, and with **no** `bin/` wrappers or env
files rewritten.

A missing `uv` must be caught the same way — that ordering matters, because cooldown validation
silently no-ops when `uv` cannot be run.

---

## Windows (PowerShell)

Run from the directory containing `install.ps1` (extracted release ZIP or repo root).

### Windows: Setup

```powershell
Remove-Item -Recurse -Force C:\Users\Quickemu\temp\mp-test -ErrorAction SilentlyContinue
```

### Test 1 — Non-isolated

```powershell
.\install.ps1 -Prefix "C:\Users\Quickemu\temp\mp-test" -Python "3.10" `
  -UvEnv "TEST_UV" -UvxEnv "TEST_UVX" -PythonEnv "TEST_PYTHON"
Get-Content C:\Users\Quickemu\temp\mp-test\distro.toml
Get-Content C:\Users\Quickemu\temp\mp-test\env.ps1
```

**Expect:** `isolated = false` and `uvx_env = "TEST_UVX"` in distro.toml; PATH added only if no system python/uv found.

### Test 2 — Isolated

```powershell
Remove-Item -Recurse -Force C:\Users\Quickemu\temp\mp-test
.\install.ps1 -Prefix "C:\Users\Quickemu\temp\mp-test" -Python "3.10" `
  -UvEnv "TEST_UV" -UvxEnv "TEST_UVX" -PythonEnv "TEST_PYTHON" -Isolated
Get-Content C:\Users\Quickemu\temp\mp-test\distro.toml
Get-Content C:\Users\Quickemu\temp\mp-test\env.ps1
& "C:\Users\Quickemu\temp\mp-test\venv\Scripts\python.exe" --version
```

**Expect:** `isolated = true`; PATH always added; python.exe is uv-managed.

### Windows: Test 3 — Idempotency

```powershell
.\install.ps1 -Prefix "C:\Users\Quickemu\temp\mp-test" -Python "3.10" `
  -UvEnv "TEST_UV" -UvxEnv "TEST_UVX" -PythonEnv "TEST_PYTHON" -Isolated
```

**Expect:** uv and venv skipped; env files regenerated.

### Windows: Test 4 — Old flag rejected

```powershell
.\install.ps1 -Prefix "C:\Users\Quickemu\temp\mp-test" -MinPython "3.10" `
  -UvEnv "TEST_UV" -UvxEnv "TEST_UVX" -PythonEnv "TEST_PYTHON"
```

**Expect:** PowerShell parameter binding error — `-MinPython` is not a recognised parameter.

### Windows: Test 5 — Package cooldown

```powershell
Remove-Item C:\Users\Quickemu\temp\mp-test -Recurse -Force
.\install.ps1 -Prefix "C:\Users\Quickemu\temp\mp-test" -Python "3.10" -EnvPrefix "TEST"
Select-String UV_EXCLUDE_NEWER C:\Users\Quickemu\temp\mp-test\env.ps1, C:\Users\Quickemu\temp\mp-test\env.bat
Select-String cooldown C:\Users\Quickemu\temp\mp-test\distro.toml
```

**Expect:** `env.ps1` contains `$env:UV_EXCLUDE_NEWER = "P1D"`, `env.bat` contains
`SET UV_EXCLUDE_NEWER=P1D`, and `distro.toml` records `cooldown = "P1D"`.

Repeat with `-Cooldown "P0D"` and expect both assignments commented out.

### Windows: Test 6 — Missing `uvx.exe` forces a re-download

The Windows half of Test 9.

```powershell
Remove-Item C:\Users\Quickemu\temp\mp-test\uvx.exe, C:\Users\Quickemu\temp\mp-test\bin\uvx.cmd -Force
.\install.ps1 -Prefix "C:\Users\Quickemu\temp\mp-test" -Python "3.10" -EnvPrefix "TEST"
. C:\Users\Quickemu\temp\mp-test\env.ps1
& $env:TEST_UVX --version
```

**Expect:** `→ Downloading uv X.Y.Z` rather than `✓ uv X.Y.Z`, `✓ venv already exists`, and
`uvx --version` prints a version. Re-running on the restored prefix must skip the download again.

---

## Testing from a release ZIP

To test the actual published artifact rather than the working tree:

```bash
# Linux / macOS
gh release download vX.Y.Z --repo redmatter/managed-python \
  --pattern "managed-python-vX.Y.Z.zip" --dir /tmp
unzip /tmp/managed-python-vX.Y.Z.zip -d /tmp/managed-python-vX.Y.Z
cd /tmp/managed-python-vX.Y.Z
# then run tests above
```

```powershell
# Windows
gh release download vX.Y.Z --repo redmatter/managed-python `
  --pattern "managed-python-vX.Y.Z.zip" `
  --dir C:\Users\Quickemu\temp
Expand-Archive C:\Users\Quickemu\temp\managed-python-vX.Y.Z.zip `
  -DestinationPath C:\Users\Quickemu\temp\managed-python-vX.Y.Z -Force
cd C:\Users\Quickemu\temp\managed-python-vX.Y.Z
# then run tests above
```
