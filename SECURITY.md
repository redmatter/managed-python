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

One further external resource is fetched during bootstrap: the pinned PyYAML wheel described in
[Pinned bootstrap dependency](#pinned-bootstrap-dependency). Nothing else is downloaded at install
time.

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
| Package cooldown (`UV_EXCLUDE_NEWER`) | Resolution of **unpinned** packages | Ignores distributions uploaded in the last 24 hours |
| Exact pin (`pyyaml==6.0.3`) | The **bootstrap** dependency | Resolves to one immutable artefact, so the cooldown has nothing to add |

The cooldown is deliberately **not** applied to the PyYAML bootstrap. A cooldown defends against a
freshly-published malicious version of a package whose version is chosen at resolve time; an exact
pin already removes that freedom, so the pin itself is the control for that dependency.

**Known limitation:** unlike the uv binary, which is SHA256-verified against the `[uv_checksums]`
block in `distro.toml`, the PyYAML wheel is **not** hash-verified. It relies on the exact pin plus
PyPI's TLS transport. This is a residual gap, not parity with uv.

## Supported Versions

Only the latest release is actively maintained.
