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

## Supported Versions

Only the latest release is actively maintained.
