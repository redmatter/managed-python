# Security Policy

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Use GitHub's private [Security Advisories](../../security/advisories/new) feature to report
vulnerabilities confidentially. We will investigate and respond as soon as we can.

## Supply Chain

`managed-python` downloads a pinned release of [uv](https://github.com/astral-sh/uv) from
GitHub. The SHA256 checksum for each platform binary is pinned in `distro.toml` under
`[uv_checksums]` and verified before the binary is extracted. The checksums are updated
automatically by `release.py` whenever `uv_version` is bumped.

Bootstrap has a small, finite download surface. Three resources are fetched during install, and
one path is deliberately closed off:

1. **The uv release archive**, SHA256-pinned against `[uv_checksums]` in `distro.toml`.
2. **The pinned PyYAML wheel** described in [Pinned bootstrap dependency](#pinned-bootstrap-dependency)
   - exact pin only, and (as disclosed below) no hash verification.
3. **A uv-managed CPython interpreter**, which `uv venv --python` downloads whenever no matching
   system Python is present. That is always the case in `--isolated` mode, and can happen in
   default mode on a host without the requested version.

The source-build path is now closed: the bootstrap installs with `--only-binary :all:`, so if no
wheel matches the pinned version uv fails loudly instead of falling back to PyYAML's sdist and
executing its build backend. Beyond the three items above, nothing is downloaded at install time.

### Package cooldown

Installs default to a **1-day package cooldown**: the generated env files export
`UV_EXCLUDE_NEWER="P1D"`, so uv ignores any distribution uploaded within the last 24 hours.
This follows the guidance in the AWS Security Blog post
[Secure your npm and pip package updates in Amazon Linux](https://aws.amazon.com/blogs/security/secure-your-npm-and-pip-package-updates-in-amazon-linux/).

Compromised releases are typically detected and yanked within hours of publication, so a short
delay removes most of the exposure window at negligible cost.

Scope and limits are documented in [README.md](README.md#package-cooldown). In brief: it covers
`uv` and `uvx` package resolution, it does **not** re-resolve an existing `uv.lock` (the lockfile's
own recorded timestamp wins until `--upgrade` or `--refresh`), and it does not apply to managed
Python interpreter downloads.

Set `--cooldown P0D` at install time to disable it, or pass `--exclude-newer P0D` on a single
command to bypass it for an urgent patch.

### Pinned bootstrap dependency

The bootstrap installs an exact, immutable release of PyYAML - pinned as `pyyaml_version` in
`distro.toml` (currently `6.0.3`) - into the managed venv. This is a **separate control** from the
package cooldown:

| Control | Governs | Mechanism |
| ------- | ------- | --------- |
| Exact pin (`pyyaml==6.0.3`) | **Which version** is selected | Removes all version-selection freedom: one immutable artefact only |
| Package cooldown (`UV_EXCLUDE_NEWER`) | **Index recency** | Filters each candidate artefact by its upload time, regardless of how the version was chosen |
| Hash pin (`[uv_checksums]`) | **Artefact identity** | Proves the bytes are the ones we expect |

These are three independent controls, and the cooldown is **not** neutralised by an exact pin. A
cooldown filters each artefact by its upload time, so a freshly-published pinned version fails to
resolve just as a freshly-published unpinned one would. Because the bootstrap previously inherited
`UV_EXCLUDE_NEWER` from the calling shell, the cooldown was being applied to the PyYAML install
non-deterministically - present in some shells, absent in others - and could make an otherwise valid
pin fail to resolve on the day it was published. This was confirmed empirically.

The bootstrap now **explicitly neutralises** the cooldown for that single install with
`--exclude-newer P0D`. The behaviour is therefore deliberate and deterministic rather than accidental:
the pin is the version-selection control for this one dependency, the cooldown still applies to
everything else, and the install no longer depends on whatever the caller's shell happened to export.
The index is likewise pinned for that install with `--no-config --default-index https://pypi.org/simple`,
so project or user config cannot redirect the fetch and the wheel can only come from PyPI over TLS.

**Known limitation:** unlike the uv binary, which is SHA256-verified against the `[uv_checksums]`
block in `distro.toml`, the PyYAML wheel is **not** hash-verified. It relies on the exact pin plus
PyPI's TLS transport. This is a residual gap, not parity with uv.

## Supported Versions

Only the latest release is actively maintained.
