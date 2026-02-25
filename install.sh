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

_bootstrap_uv() {
    local prefix="$1" uv_version="$2"
    local uv_bin="${prefix}/uv"

    if [[ -x "$uv_bin" ]] && \
       [[ "$("$uv_bin" --version 2>/dev/null | awk '{print $2}')" == "$uv_version" ]]; then
        _msg "  ✓ uv $uv_version"; return
    fi

    _msg "  → Downloading uv $uv_version"
    local url tmp
    url="$(_uv_download_url "$uv_version")"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "${tmp}/uv.tar.gz"
    elif command -v wget &>/dev/null; then
        wget -qO "${tmp}/uv.tar.gz" "$url"
    else
        printf "ERROR: curl or wget required\n" >&2; exit 1
    fi

    tar -xzf "${tmp}/uv.tar.gz" -C "$tmp"
    mkdir -p "$prefix"
    cp "$(find "$tmp" -name "uv" -type f | head -1)" "$uv_bin"
    chmod +x "$uv_bin"
    _msg "  ✓ uv $uv_version installed"
}

_bootstrap_venv() {
    local prefix="$1" min_python="$2"

    if [[ -x "${prefix}/venv/bin/python" ]]; then
        _msg "  ✓ venv already exists"; return
    fi

    _msg "  → Creating Python $min_python venv"
    "${prefix}/uv" venv --python "$min_python" "${prefix}/venv"
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
    local i
    for (( i=1; i<=$#; i++ )); do
        case "${!i}" in
            --prefix)     j=$((i+1)); prefix="${!j}";      prefix="${prefix/#\~/$HOME}" ;;
            --min-python) j=$((i+1)); min_python="${!j}" ;;
            --quiet|-q)   quiet=1 ;;
        esac
    done

    [[ -z "$prefix" ]]     && { printf "ERROR: --prefix is required\n" >&2; exit 1; }
    [[ -z "$min_python" ]] && { printf "ERROR: --min-python is required\n" >&2; exit 1; }

    _msg ""
    _msg "managed-python bootstrap"
    _msg "  prefix  $prefix"
    _msg ""

    _bootstrap_uv   "$prefix" "$uv_version"
    _bootstrap_venv "$prefix" "$min_python"

    _msg ""
    exec "${prefix}/venv/bin/python" "${script_dir}/setup.py" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
