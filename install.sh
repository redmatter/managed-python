#!/usr/bin/env bash
# install.sh — Bootstrap uv + Python venv, then hand off to setup.py
#
# Usage:
#   ./install.sh --prefix PATH --min-python X.Y --uv-env NAME --python-env NAME [--shell-profile]
#
# Bootstrap phase (this script): download uv, create venv.
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
    grep "^${target}" "$distro_toml" \
        | sed -E 's/^[^=]+=\s*"([^"]+)".*/\1/'
}

_bootstrap_uv() {
    local prefix="$1" uv_version="$2" distro_toml="$3"
    local uv_bin="${prefix}/uv"

    if [[ -x "$uv_bin" ]] && \
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
    trap 'rm -rf "$tmp"; trap - RETURN' RETURN

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
    _msg "  ✓ uv $uv_version installed"
}

_bootstrap_venv() {
    local prefix="$1" min_python="$2"

    if [[ -x "${prefix}/venv/bin/python" ]]; then
        _msg "  ✓ venv already exists"; return
    fi

    _msg "  → Creating Python $min_python venv"
    "${prefix}/uv" venv --python "$min_python" ${quiet:+--quiet} "${prefix}/venv" \
        || { printf "ERROR: Failed to create Python %s venv — see uv error above\n" "$min_python" >&2; exit 1; }
    _msg "  ✓ venv created"
}

main() {
    set -euo pipefail

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    local uv_version
    uv_version="$(grep '^uv_version' "${script_dir}/distro.toml" \
        | sed -E 's/^[^=]+=\s*"?([^"#]+)"?.*/\1/' | tr -d '[:space:]')"

    # Extract --prefix, --min-python, and --quiet for bootstrap (all flags forwarded to setup.py)
    local prefix="" min_python="" quiet=""
    local i j
    for (( i=1; i<=$#; i++ )); do
        case "${!i}" in
            --prefix)
                j=$((i+1))
                if (( j > $# )); then printf "ERROR: --prefix requires a value\n" >&2; exit 1; fi
                prefix="${!j}"; prefix="${prefix/#\~/$HOME}" ;;
            --min-python)
                j=$((i+1))
                if (( j > $# )); then printf "ERROR: --min-python requires a value\n" >&2; exit 1; fi
                min_python="${!j}" ;;
            --quiet|-q) quiet=1 ;;
        esac
    done

    [[ -z "$prefix" ]]     && { printf "ERROR: --prefix is required\n" >&2; exit 1; }
    [[ -z "$min_python" ]] && { printf "ERROR: --min-python is required\n" >&2; exit 1; }

    _msg ""
    _msg "managed-python bootstrap"
    _msg "  prefix  $prefix"
    _msg ""

    _bootstrap_uv   "$prefix" "$uv_version" "${script_dir}/distro.toml"
    _bootstrap_venv "$prefix" "$min_python"

    _msg ""
    exec "${prefix}/venv/bin/python" "${script_dir}/setup.py" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
