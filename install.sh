#!/usr/bin/env bash
# install.sh — Bootstrap uv + Python venv, then hand off to setup.py
#
# Usage:
#   ./install.sh --prefix PATH --python X.Y --uv-env NAME --python-env NAME \
#                [--cooldown DURATION] [--isolated] [--shell-profile]
#
# Bootstrap phase (this script): download uv, create venv, install the pinned pyyaml.
# Configuration phase (setup.py): env.sh, env.ps1, bin/ wrappers, shell profile.

_msg() { [ "${quiet:-}" != "1" ] && printf "%s\n" "$1"; return 0; }

_uv_download_url() {
    local uv_version="$1" os arch target
    case "$(uname -s)" in
        Linux)  os=linux ;;
        Darwin) os=macos ;;
        *)      printf "Unsupported OS: %s\n" "$(uname -s)" >&2; return 1 ;;
    esac
    case "$(uname -m)" in
        x86_64)        arch=x86_64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *)             printf "Unsupported arch: %s\n" "$(uname -m)" >&2; return 1 ;;
    esac
    [[ "$os" == linux ]] \
        && target="${arch}-unknown-linux-gnu" \
        || target="${arch}-apple-darwin"
    printf "https://github.com/astral-sh/uv/releases/download/%s/uv-%s.tar.gz" \
        "$uv_version" "$target"
}

_uv_expected_hash() {
    local distro_toml="$1" target="$2"
    # The trailing `|| true` is load-bearing: under `set -e` plus `pipefail` a
    # non-zero grep (target absent) would otherwise abort the caller before it
    # can print its diagnostic, so the caller's own guard is the authority.
    grep "^${target}" "$distro_toml" \
        | sed -E 's/^[^=]+=[[:space:]]*"([^"]+)".*/\1/' || true
}

# Read a quoted key=value out of distro.toml: exact key, optional leading
# whitespace, optional whitespace around "=", and an optional trailing comment.
# It deliberately does NOT tidy the value - whatever sits between the quotes is
# returned verbatim, so the caller's own validation is the only thing deciding
# what is acceptable. The `|| true` keeps `set -e` plus `pipefail` from aborting
# the caller on absent or unreadable input, leaving its diagnostic free to fire.
# A duplicated key therefore comes back as a multi-line value; `main` rejects that
# outright by counting matches first, and install.ps1 mirrors the same check.
_distro_value() {
    local distro_toml="$1" key="$2"
    sed -nE 's/^[[:space:]]*'"${key}"'[[:space:]]*=[[:space:]]*"([^"]+)"[[:space:]]*(#.*)?$/\1/p' \
        "$distro_toml" || true
}

_bootstrap_uv() {
    local prefix="$1" uv_version="$2" distro_toml="$3"
    local uv_bin="${prefix}/uv"

    # Both binaries must be present, not just uv - a prefix from before uvx
    # existed can match the pinned version yet have no uvx at all, and a
    # version-only check would happily skip the download and leave it missing.
    # A missing uvx therefore re-downloads the pair; they ship in one archive.
    if [[ -x "$uv_bin" ]] && [[ -x "${prefix}/uvx" ]] && \
       [[ "$("$uv_bin" --version 2>/dev/null | awk '{print $2}')" == "$uv_version" ]]; then
        _msg "  ✓ uv $uv_version"; return
    fi

    _msg "  → Downloading uv $uv_version"
    local url tmp target
    url="$(_uv_download_url "$uv_version")"
    # Derive target triple from the URL for checksum lookup (strip leading "uv-")
    target="$(basename "$url" .tar.gz)"
    target="${target#uv-}"
    tmp="$(mktemp -d)"
    # An EXIT trap, not RETURN: RETURN never fires when a later guard calls
    # `exit 1`, so the downloaded archive would be left behind in TMPDIR on
    # every failure path. On success the archive has already been copied out of
    # $tmp, so removing it at script exit is correct and harmless.
    trap 'rm -rf "$tmp"' EXIT

    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "${tmp}/uv.tar.gz" \
            || { printf "ERROR: Failed to download uv %s\n" "$uv_version" >&2; exit 1; }
    elif command -v wget &>/dev/null; then
        wget -qO "${tmp}/uv.tar.gz" "$url" \
            || { printf "ERROR: Failed to download uv %s\n" "$uv_version" >&2; exit 1; }
    else
        printf "ERROR: curl or wget required\n" >&2; exit 1
    fi

    local expected_hash actual_hash
    expected_hash="$(_uv_expected_hash "$distro_toml" "$target")"
    if [[ -z "$expected_hash" ]]; then
        printf "ERROR: no pinned checksum for target %s in distro.toml\n" "$target" >&2; exit 1
    fi
    if command -v sha256sum &>/dev/null; then
        actual_hash="$(sha256sum "${tmp}/uv.tar.gz" | awk '{print $1}')"
    elif command -v shasum &>/dev/null; then
        actual_hash="$(shasum -a 256 "${tmp}/uv.tar.gz" | awk '{print $1}')"
    else
        printf "ERROR: sha256sum or shasum is required for checksum verification\n" >&2; exit 1
    fi
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        printf "ERROR: uv %s checksum verification failed\n  expected: %s\n  actual:   %s\n" \
            "$uv_version" "$expected_hash" "$actual_hash" >&2; exit 1
    fi

    tar -xzf "${tmp}/uv.tar.gz" -C "$tmp"
    mkdir -p "$prefix"
    local uv_src
    uv_src="$(find "$tmp" -name "uv" -type f | head -1 || true)"
    if [[ -z "$uv_src" || ! -f "$uv_src" ]]; then
        printf "ERROR: failed to locate uv binary in downloaded archive\n" >&2; exit 1
    fi
    cp "$uv_src" "$uv_bin"
    chmod +x "$uv_bin"
    local uvx_src
    uvx_src="$(find "$tmp" -name "uvx" -type f | head -1 || true)"
    if [[ -z "$uvx_src" || ! -f "$uvx_src" ]]; then
        printf "ERROR: failed to locate uvx binary in downloaded archive\n" >&2; exit 1
    fi
    cp "$uvx_src" "${prefix}/uvx"
    chmod +x "${prefix}/uvx"
    _msg "  ✓ uv $uv_version installed"
}

_bootstrap_venv() {
    local prefix="$1" min_python="$2" isolated="${3:-}"

    if [[ -x "${prefix}/venv/bin/python" ]]; then
        _msg "  ✓ venv already exists"; return
    fi

    _msg "  → Creating Python $min_python venv"
    local pref_args="--python-preference system"
    [[ "$isolated" == "1" ]] && pref_args="--python-preference only-managed"
    "${prefix}/uv" venv --python "$min_python" $pref_args ${quiet:+--quiet} "${prefix}/venv" \
        || { printf "ERROR: Failed to create Python %s venv — see uv error above\n" "$min_python" >&2; exit 1; }
    _msg "  ✓ venv created"
}

# Pre-install the pinned pyyaml into the venv, so the venv is useful before
# setup.py runs. Parameters: $1 = install prefix, $2 = pinned version (empty
# skips this step; main already rejects an empty pin, so this is belt-and-braces
# for any other caller). Returns 0 when already satisfied, installs via uv
# otherwise; exits 1 if the install fails, since a half-provisioned venv is not
# a state we want to hand off to setup.py.
_bootstrap_packages() {
    local prefix="$1" pyyaml_version="$2"
    # An explicit if-block, not a trailing `&&`: a bare `[[ ]] && return 0` is
    # fine here only while it is not the last statement, and that is a trap for
    # whoever adds a line below it later.
    if [[ -z "$pyyaml_version" ]]; then
        return 0
    fi

    local venv_py="${prefix}/venv/bin/python"
    # `-I` (isolated mode) matters here: without it a stray yaml.py in the
    # working directory or on PYTHONPATH could answer for the pinned package,
    # and the probe would wrongly report the venv already satisfied.
    if [[ -x "$venv_py" ]] && "$venv_py" -I -c "import sys, yaml; sys.exit(0 if yaml.__version__ == sys.argv[1] else 1)" "$pyyaml_version" &>/dev/null; then
        _msg "  ✓ pyyaml $pyyaml_version"; return
    fi

    _msg "  → Installing pyyaml $pyyaml_version"
    # Each flag here closes a specific way the bootstrap could hard-fail or
    # fetch something other than the pinned wheel:
    #   --exclude-newer P0D      neutralises any inherited UV_EXCLUDE_NEWER
    #                            (a shell that sourced env.sh exports P1D, which
    #                            would filter out the pinned wheel entirely)
    #   --no-config --default-index https://pypi.org/simple
    #                            pins the index, so a uv.toml in the working
    #                            directory or UV_DEFAULT_INDEX cannot redirect
    #                            the download elsewhere
    #   --only-binary :all:      fails closed when no wheel matches, rather than
    #                            silently compiling the sdist
    # `--python "${prefix}/venv"` is deliberate: uv accepts the venv directory as
    # well as the interpreter path, and TESTING.md clones this exact directory form.
    "${prefix}/uv" pip install --python "${prefix}/venv" \
        --exclude-newer P0D --no-config --default-index https://pypi.org/simple --only-binary :all: \
        "pyyaml==${pyyaml_version}" ${quiet:+--quiet} \
        || { printf "ERROR: Failed to install pyyaml %s\n" "$pyyaml_version" >&2; exit 1; }
    _msg "  ✓ pyyaml $pyyaml_version installed"
}

main() {
    set -euo pipefail

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    local uv_version pyyaml_version
    uv_version="$(_distro_value "${script_dir}/distro.toml" uv_version)"
    pyyaml_version="$(_distro_value "${script_dir}/distro.toml" pyyaml_version)"

    # A duplicated key is a merge accident, not a value: reject it loudly rather
    # than let one of the two silently win. Fail-fast matches the validation below.
    local key count
    for key in uv_version pyyaml_version; do
        count="$(grep -cE "^[[:space:]]*${key}[[:space:]]*=" "${script_dir}/distro.toml" || true)"
        if [[ "${count:-0}" -gt 1 ]]; then
            printf "ERROR: %s appears %s times in %s/distro.toml (expected exactly one)\n" \
                "$key" "$count" "$script_dir" >&2; exit 1
        fi
    done

    if [[ -z "$uv_version" ]]; then
        printf "ERROR: uv_version is missing in %s/distro.toml\n" "$script_dir" >&2; exit 1
    fi
    if [[ -z "$pyyaml_version" ]]; then
        printf "ERROR: pyyaml_version is missing in %s/distro.toml\n" "$script_dir" >&2; exit 1
    fi

    # Reject anything that is not a plain digits-and-dots version. The value is
    # interpolated into a package specifier, so a malformed hand-edit - a
    # pre-release suffix, or a leading "-" that uv would read as an option -
    # must never reach the install command.
    if [[ ! "$uv_version" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
        printf "ERROR: uv_version %q in %s/distro.toml is not a valid version\n" \
            "$uv_version" "$script_dir" >&2; exit 1
    fi
    if [[ ! "$pyyaml_version" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
        printf "ERROR: pyyaml_version %q in %s/distro.toml is not a valid version\n" \
            "$pyyaml_version" "$script_dir" >&2; exit 1
    fi

    # Extract --prefix, --python, --isolated, and --quiet for bootstrap (all flags forwarded to setup.py)
    local prefix="" min_python="" isolated="" quiet=""
    local i j
    for (( i=1; i<=$#; i++ )); do
        case "${!i}" in
            --prefix)
                j=$((i+1))
                if (( j > $# )); then printf "ERROR: --prefix requires a value\n" >&2; exit 1; fi
                prefix="${!j}"; prefix="${prefix/#\~/$HOME}" ;;
            --python)
                j=$((i+1))
                if (( j > $# )); then printf "ERROR: --python requires a value\n" >&2; exit 1; fi
                min_python="${!j}" ;;
            --isolated) isolated=1 ;;
            --quiet|-q) quiet=1 ;;
        esac
    done

    [[ -z "$prefix" ]]     && { printf "ERROR: --prefix is required\n" >&2; exit 1; }
    [[ -z "$min_python" ]] && { printf "ERROR: --python is required\n" >&2; exit 1; }

    # Internal tooling requires 3.12 or newer: the pinned PyYAML wheels cover CPython
    # 3.12, 3.13 and 3.14 only, so an older interpreter with no matching wheel would
    # fall back to a source build.
    if [[ "$(printf '%s\n%s\n' "3.12" "$min_python" | sort -V | head -1)" != "3.12" ]]; then
        printf "ERROR: --python %s is below the supported floor of 3.12\n" "$min_python" >&2; exit 1
    fi

    _msg ""
    _msg "managed-python bootstrap"
    _msg "  prefix  $prefix"
    _msg ""

    _bootstrap_uv   "$prefix" "$uv_version" "${script_dir}/distro.toml"
    _bootstrap_venv "$prefix" "$min_python" "$isolated"
    _bootstrap_packages "$prefix" "$pyyaml_version"

    _msg ""
    # All flags (including --env-prefix / --uv-env / --uvx-env / --python-env) are forwarded
    # verbatim to setup.py, which owns env var name resolution and validation.
    exec "${prefix}/venv/bin/python" "${script_dir}/setup.py" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
