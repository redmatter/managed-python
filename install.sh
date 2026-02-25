#!/usr/bin/env bash
# install.sh — managed-python bootstrap for Linux/macOS
#
# Usage:
#   ./install.sh \
#     --prefix ~/.claude/redmatter/python \
#     --min-python 3.10 \
#     --uv-env REDMATTER_UV \
#     --python-env REDMATTER_PYTHON \
#     [--shell-profile]
#
# Installs uv (pinned version from distro.toml) and creates a Python venv
# at the given prefix. Writes env.sh that exports env vars and optionally
# adds prefix/bin to PATH.

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISTRO_TOML="${SCRIPT_DIR}/distro.toml"

# ---------------------------------------------------------------------------
# Parse distro.toml (no external deps — pure bash)
# ---------------------------------------------------------------------------
parse_toml_value() {
    local file="$1"
    local key="$2"
    grep -E "^${key}\s*=" "$file" | sed -E 's/^[^=]+=\s*"?([^"#]+)"?.*/\1/' | tr -d '[:space:]'
}

DISTRO_VERSION="$(parse_toml_value "$DISTRO_TOML" version)"
UV_VERSION="$(parse_toml_value "$DISTRO_TOML" uv_version)"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
PREFIX=""
MIN_PYTHON=""
UV_ENV_NAME=""
PYTHON_ENV_NAME=""
SHELL_PROFILE=false

usage() {
    cat >&2 <<EOF
Usage: $0 --prefix PATH --min-python X.Y --uv-env NAME --python-env NAME [--shell-profile]

Required:
  --prefix PATH       Install location for uv binary, venv, and env.sh
  --min-python X.Y    Minimum Python version for the venv (e.g. 3.10)
  --uv-env NAME       Name of env var to export for the uv binary path
  --python-env NAME   Name of env var to export for the python binary path

Optional:
  --shell-profile     Append 'source <prefix>/env.sh' to detected shell rc file
  --help              Show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)       PREFIX="$2";         shift 2 ;;
        --min-python)   MIN_PYTHON="$2";     shift 2 ;;
        --uv-env)       UV_ENV_NAME="$2";    shift 2 ;;
        --python-env)   PYTHON_ENV_NAME="$2"; shift 2 ;;
        --shell-profile) SHELL_PROFILE=true; shift ;;
        --help|-h)      usage ;;
        *) echo "Unknown flag: $1" >&2; usage ;;
    esac
done

[[ -z "$PREFIX" ]]          && { echo "ERROR: --prefix is required" >&2; usage; }
[[ -z "$MIN_PYTHON" ]]      && { echo "ERROR: --min-python is required" >&2; usage; }
[[ -z "$UV_ENV_NAME" ]]     && { echo "ERROR: --uv-env is required" >&2; usage; }
[[ -z "$PYTHON_ENV_NAME" ]] && { echo "ERROR: --python-env is required" >&2; usage; }

# Expand tilde in prefix
PREFIX="${PREFIX/#\~/$HOME}"

# ---------------------------------------------------------------------------
# Derived paths
# ---------------------------------------------------------------------------
UV_BIN="${PREFIX}/uv"
VENV_DIR="${PREFIX}/venv"
VENV_PYTHON="${VENV_DIR}/bin/python"
BIN_DIR="${PREFIX}/bin"
ENV_SH="${PREFIX}/env.sh"
ENV_PS1="${PREFIX}/env.ps1"
DISTRO_TOML_DEST="${PREFIX}/distro.toml"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
print_step() { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
print_ok()   { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
print_info() { printf "  \033[0;36mℹ\033[0m %s\n" "$*"; }
print_warn() { printf "  \033[0;33m⚠\033[0m %s\n" "$*"; }

# ---------------------------------------------------------------------------
# Detect platform for uv download URL
# ---------------------------------------------------------------------------
detect_uv_url() {
    local os arch

    case "$(uname -s)" in
        Linux)  os="linux" ;;
        Darwin) os="macos" ;;
        *)      echo "ERROR: Unsupported OS: $(uname -s)" >&2; exit 1 ;;
    esac

    case "$(uname -m)" in
        x86_64)          arch="x86_64" ;;
        aarch64|arm64)   arch="aarch64" ;;
        *)               echo "ERROR: Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
    esac

    # uv release asset naming convention
    echo "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${arch}-${os}-$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/darwin/apple-darwin/' | sed 's/linux/unknown-linux-gnu/').tar.gz"
}

# More precise URL builder matching actual uv release naming
build_uv_download_url() {
    local os arch target

    case "$(uname -s)" in
        Linux)  os="linux" ;;
        Darwin) os="macos" ;;
        *)      echo "ERROR: Unsupported OS: $(uname -s)" >&2; exit 1 ;;
    esac

    case "$(uname -m)" in
        x86_64)        arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *)             echo "ERROR: Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
    esac

    if [[ "$os" == "linux" ]]; then
        target="${arch}-unknown-linux-gnu"
    else
        target="${arch}-apple-darwin"
    fi

    echo "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${target}.tar.gz"
}

# ---------------------------------------------------------------------------
# Step 1: Download uv (if needed or version mismatch)
# ---------------------------------------------------------------------------
install_uv() {
    print_step "Installing uv ${UV_VERSION}"

    # Check if current uv already matches pinned version
    if [[ -x "$UV_BIN" ]]; then
        local current_ver
        current_ver="$("$UV_BIN" --version 2>/dev/null | awk '{print $2}' || true)"
        if [[ "$current_ver" == "$UV_VERSION" ]]; then
            print_ok "uv ${UV_VERSION} already installed — skipping download"
            return
        fi
        print_info "Updating uv ${current_ver} → ${UV_VERSION}"
    fi

    mkdir -p "$PREFIX"

    local url
    url="$(build_uv_download_url)"
    print_info "Downloading from: ${url}"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "${tmp_dir}/uv.tar.gz"
    elif command -v wget &>/dev/null; then
        wget -qO "${tmp_dir}/uv.tar.gz" "$url"
    else
        echo "ERROR: Neither curl nor wget found. Cannot download uv." >&2
        exit 1
    fi

    tar -xzf "${tmp_dir}/uv.tar.gz" -C "$tmp_dir"

    # uv tarball contains uv-<target>/uv binary
    local uv_bin
    uv_bin="$(find "$tmp_dir" -name "uv" -type f | head -1)"
    if [[ -z "$uv_bin" ]]; then
        echo "ERROR: Could not find uv binary in downloaded archive." >&2
        exit 1
    fi

    cp "$uv_bin" "$UV_BIN"
    chmod +x "$UV_BIN"
    print_ok "uv ${UV_VERSION} installed to ${UV_BIN}"
}

# ---------------------------------------------------------------------------
# Step 2: Create Python venv
# ---------------------------------------------------------------------------
create_venv() {
    print_step "Creating Python venv (>= ${MIN_PYTHON})"

    if [[ -x "$VENV_PYTHON" ]]; then
        local current_ver
        current_ver="$("$VENV_PYTHON" --version 2>&1 | awk '{print $2}' || true)"
        print_ok "Python venv already exists (${current_ver}) — skipping creation"
        return
    fi

    "$UV_BIN" venv --python "${MIN_PYTHON}" "$VENV_DIR"
    print_ok "Venv created at ${VENV_DIR}"

    local actual_ver
    actual_ver="$("$VENV_PYTHON" --version 2>&1 | awk '{print $2}')"
    print_ok "Python version: ${actual_ver}"
}

# ---------------------------------------------------------------------------
# Step 3: Create bin/ symlinks
# ---------------------------------------------------------------------------
create_bin_symlinks() {
    print_step "Creating bin/ symlinks"

    mkdir -p "$BIN_DIR"

    # python symlink
    ln -sf "../venv/bin/python" "${BIN_DIR}/python"
    print_ok "bin/python -> ../venv/bin/python"

    # uv symlink
    ln -sf "../uv" "${BIN_DIR}/uv"
    print_ok "bin/uv -> ../uv"
}

# ---------------------------------------------------------------------------
# Step 4: Determine PATH logic and write env.sh
# ---------------------------------------------------------------------------
write_env_sh() {
    print_step "Writing env.sh"

    local python_on_path=false
    local uv_on_path=false

    if command -v python &>/dev/null || command -v python3 &>/dev/null; then
        python_on_path=true
    fi
    if command -v uv &>/dev/null; then
        uv_on_path=true
    fi

    local add_to_path=true
    local path_note=""

    if $python_on_path && $uv_on_path; then
        add_to_path=false
        path_note="# python and uv already on PATH. To use managed versions:
# export PATH=\"${BIN_DIR}:\$PATH\""
    elif $python_on_path; then
        local sys_python
        sys_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
        path_note="# Note: system python found at ${sys_python} — will be shadowed by managed version"
    elif $uv_on_path; then
        local sys_uv
        sys_uv="$(command -v uv 2>/dev/null || true)"
        path_note="# Note: system uv found at ${sys_uv} — will be shadowed by managed version"
    fi

    cat > "$ENV_SH" <<EOF
# managed-python v${DISTRO_VERSION} — generated by install.sh
# Do not edit manually; re-run install.sh to regenerate

# Env vars (always set — these are the reliable contract)
export ${UV_ENV_NAME}="${UV_BIN}"
export ${PYTHON_ENV_NAME}="${VENV_PYTHON}"

EOF

    if $add_to_path; then
        [[ -n "$path_note" ]] && printf "%s\n\n" "$path_note" >> "$ENV_SH"
        cat >> "$ENV_SH" <<EOF
# PATH (added because python/uv were not already on system PATH)
export PATH="${BIN_DIR}:\$PATH"
EOF
    else
        printf "%s\n" "$path_note" >> "$ENV_SH"
    fi

    chmod 644 "$ENV_SH"
    print_ok "env.sh written to ${ENV_SH}"

    # Console output for PATH decision
    if $add_to_path; then
        if ! $python_on_path && ! $uv_on_path; then
            print_info "Added python and uv to PATH via ${BIN_DIR}"
        elif $python_on_path; then
            print_warn "system python found — managed version will shadow it when env.sh is sourced"
        elif $uv_on_path; then
            print_warn "system uv found — managed version will shadow it when env.sh is sourced"
        fi
    else
        print_info "python and uv already on PATH — PATH not modified"
        print_info "To use managed versions: export PATH=\"${BIN_DIR}:\$PATH\""
    fi
}

# ---------------------------------------------------------------------------
# Step 5: Write env.ps1 (PowerShell equivalent)
# ---------------------------------------------------------------------------
write_env_ps1() {
    print_step "Writing env.ps1"

    # Determine PowerShell PATH logic (same logic as env.sh)
    local python_on_path=false
    local uv_on_path=false
    if command -v python &>/dev/null || command -v python3 &>/dev/null; then python_on_path=true; fi
    if command -v uv &>/dev/null; then uv_on_path=true; fi
    local add_to_path=true
    if $python_on_path && $uv_on_path; then add_to_path=false; fi

    cat > "$ENV_PS1" <<EOF
# managed-python v${DISTRO_VERSION} — generated by install.sh
# Do not edit manually; re-run install.sh to regenerate

# Env vars (always set — these are the reliable contract)
\$env:${UV_ENV_NAME} = "${UV_BIN}"
\$env:${PYTHON_ENV_NAME} = "${VENV_PYTHON}"

EOF

    if $add_to_path; then
        cat >> "$ENV_PS1" <<EOF
# PATH (added because python/uv were not already on system PATH)
\$env:PATH = "${BIN_DIR}:" + \$env:PATH
EOF
    else
        cat >> "$ENV_PS1" <<EOF
# python and uv already on PATH. To use managed versions:
# \$env:PATH = "${BIN_DIR}:" + \$env:PATH
EOF
    fi

    chmod 644 "$ENV_PS1"
    print_ok "env.ps1 written to ${ENV_PS1}"
}

# ---------------------------------------------------------------------------
# Step 6: Copy distro.toml to prefix
# ---------------------------------------------------------------------------
copy_distro_toml() {
    cp "$DISTRO_TOML" "$DISTRO_TOML_DEST"
    print_ok "distro.toml copied to ${DISTRO_TOML_DEST}"
}

# ---------------------------------------------------------------------------
# Step 7: Optionally append source to shell rc
# ---------------------------------------------------------------------------
append_shell_profile() {
    if ! $SHELL_PROFILE; then
        return
    fi

    print_step "Updating shell profile"

    local shell_rc=""
    case "${SHELL:-}" in
        */zsh)  shell_rc="${HOME}/.zshrc" ;;
        */bash) shell_rc="${HOME}/.bashrc" ;;
        *)
            # Detect available rc files
            if [[ -f "${HOME}/.zshrc" ]]; then
                shell_rc="${HOME}/.zshrc"
            elif [[ -f "${HOME}/.bashrc" ]]; then
                shell_rc="${HOME}/.bashrc"
            fi
            ;;
    esac

    if [[ -z "$shell_rc" ]]; then
        print_warn "Could not detect shell rc file. Add manually:"
        print_info "  source \"${ENV_SH}\""
        return
    fi

    local source_line="source \"${ENV_SH}\""

    # Avoid duplicate entries
    if grep -qF "$source_line" "$shell_rc" 2>/dev/null; then
        print_ok "Shell profile already configured: ${shell_rc}"
        return
    fi

    printf '\n# managed-python\n%s\n' "$source_line" >> "$shell_rc"
    print_ok "Appended to ${shell_rc}"
    print_info "Restart your shell or run: source \"${ENV_SH}\""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo "managed-python v${DISTRO_VERSION}"
    echo "  prefix  ${PREFIX}"
    echo "  uv      ${UV_VERSION}   python >= ${MIN_PYTHON}"
    echo ""

    install_uv
    create_venv
    create_bin_symlinks
    write_env_sh
    write_env_ps1
    copy_distro_toml
    append_shell_profile

    echo ""
    echo "┌─────────────────────────────────────────┐"
    echo "│  Install complete!                       │"
    echo "└─────────────────────────────────────────┘"
    echo ""
    echo "  source \"${ENV_SH}\""
    echo ""
    echo "  Then:  \"\$${PYTHON_ENV_NAME}\" /path/to/script.py"
    echo "         \"\$${UV_ENV_NAME}\" run --project /path/to/app script.py"
    echo ""
}

main
