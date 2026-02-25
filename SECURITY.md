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

No other external resources are downloaded at install time.

## Supported Versions

Only the latest release is actively maintained.
