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
