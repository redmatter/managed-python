#!/usr/bin/env python3
"""
setup.py — Post-bootstrap configuration for managed-python.

Pure stdlib. No external dependencies.

Invoked by install.sh / install.ps1 after uv and the venv have been
created. Handles everything that does not require platform-specific
shell syntax: bin/ wrappers, env.sh, env.ps1, distro.toml copy, and
optional shell profile update.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

_IS_WINDOWS = sys.platform == "win32"
_QUIET = False


# ── TOML (minimal key=value reader, no deps) ─────────────────────────────────

def _toml_get(path: Path, key: str) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith(key) and "=" in stripped:
            _, _, raw = stripped.partition("=")
            return raw.split("#")[0].strip().strip('"')
    raise KeyError(f"{key!r} not found in {path}")


# ── Output ────────────────────────────────────────────────────────────────────

def _banner(msg: str) -> None:
    if _QUIET:
        return
    width = len(msg) + 4  # 2 spaces padding each side
    print(f"┌{'─' * width}┐")
    print(f"│  {msg}  │")
    print(f"└{'─' * width}┘")


def _ok(msg: str) -> None:
    if _QUIET:
        return
    print(f"  \u2713 {msg}")


def _info(msg: str) -> None:
    if _QUIET:
        return
    print(f"  \u2139 {msg}")


def _warn(msg: str) -> None:
    print(f"  \u26a0 {msg}")


def _step(msg: str) -> None:
    if _QUIET:
        return
    print(f"\n==> {msg}")


# ── PATH detection ────────────────────────────────────────────────────────────

def _path_decision(bin_dir: Path) -> tuple[bool, list[str]]:
    """Decide whether to add bin_dir to PATH in generated env files.

    Args:
        bin_dir: The managed-python bin/ directory to conditionally add to PATH.

    Returns:
        Tuple of (add_to_path, note_lines) where add_to_path is True when the
        bin directory should be prepended to PATH, and note_lines is a list of
        human-readable notes explaining the decision.
    """
    def _real_executable(path: str | None) -> str | None:
        """Return path only if it is a non-empty file (filters Windows App Execution Alias stubs)."""
        if not path:
            return None
        try:
            if Path(path).stat().st_size > 0:
                return path
        except OSError:
            return None
        return None

    python_found = _real_executable(shutil.which("python")) or _real_executable(shutil.which("python3"))
    uv_found = _real_executable(shutil.which("uv"))

    if python_found and uv_found:
        if _IS_WINDOWS:
            path_hint = f'To use managed versions: $env:PATH = "{bin_dir};" + $env:PATH'
        else:
            path_hint = f'To use managed versions: export PATH="{bin_dir}:$PATH"'
        return False, [
            "python and uv already on PATH — PATH not modified",
            path_hint,
        ]

    notes: list[str] = []
    if python_found:
        notes.append(f"system python found at {python_found} — will be shadowed by managed version")
    if uv_found:
        notes.append(f"system uv found at {uv_found} — will be shadowed by managed version")
    return True, notes


# ── bin/ wrappers ─────────────────────────────────────────────────────────────

def _symlink(link: Path, target: Path) -> None:
    if link.is_symlink() or link.exists():
        link.unlink()
    link.symlink_to(target)


def _create_bin(prefix: Path) -> None:
    _step("Creating bin/ wrappers")
    bin_dir = prefix / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)

    if _IS_WINDOWS:
        uv_exe  = prefix / "uv.exe"
        uvx_exe = prefix / "uvx.exe"
        venv_py = prefix / "venv" / "Scripts" / "python.exe"
        (bin_dir / "python.cmd").write_text(f'@"{venv_py}" %*\n', encoding="utf-8")
        (bin_dir / "uv.cmd").write_text(f'@"{uv_exe}" %*\n', encoding="utf-8")
        (bin_dir / "uvx.cmd").write_text(f'@"{uvx_exe}" %*\n', encoding="utf-8")
        _ok("bin\\python.cmd")
        _ok("bin\\uv.cmd")
        _ok("bin\\uvx.cmd")
    else:
        _symlink(bin_dir / "python", Path("../venv/bin/python"))
        _symlink(bin_dir / "uv",     Path("../uv"))
        _symlink(bin_dir / "uvx",    Path("../uvx"))
        _ok("bin/python \u2192 ../venv/bin/python")
        _ok("bin/uv \u2192 ../uv")
        _ok("bin/uvx \u2192 ../uvx")


# ── env.sh ────────────────────────────────────────────────────────────────────

def _write_env_sh(prefix: Path, uv_env: str, uvx_env: str, python_env: str, distro_version: str, *, isolated: bool = False) -> None:
    if _IS_WINDOWS:
        _info("Skipping env.sh on Windows — use env.ps1 instead")
        return
    _step("Writing env.sh")

    uv_bin  = prefix / "uv"
    uvx_bin = prefix / "uvx"
    venv_py = prefix / "venv" / "bin" / "python"
    bin_dir = prefix / "bin"

    if isolated:
        add_to_path = True
        notes = ["--isolated: always adding bin/ to PATH"]
    else:
        add_to_path, notes = _path_decision(bin_dir)

    lines: list[str] = [
        f"# managed-python v{distro_version} \u2014 generated by setup.py",
        "# Do not edit manually; re-run install.sh to regenerate",
        "",
        "# Env vars (always set \u2014 these are the reliable contract)",
        f'export {uv_env}="{uv_bin}"',
        f'export {uvx_env}="{uvx_bin}"',
        f'export {python_env}="{venv_py}"',
        "",
    ]

    if add_to_path:
        lines += [f"# {n}" for n in notes]
        lines.append(f'export PATH="{bin_dir}:$PATH"')
    else:
        lines += [f"# {n}" for n in notes]

    (prefix / "env.sh").write_text("\n".join(lines) + "\n", encoding="utf-8")
    _ok("env.sh")
    for note in notes:
        (_warn if "shadowed" in note else _info)(note)


# ── env.ps1 ───────────────────────────────────────────────────────────────────

def _write_env_ps1(prefix: Path, uv_env: str, uvx_env: str, python_env: str, distro_version: str, *, isolated: bool = False) -> None:
    _step("Writing env.ps1")

    uv_exe  = prefix / ("uv.exe" if _IS_WINDOWS else "uv")
    uvx_exe = prefix / ("uvx.exe" if _IS_WINDOWS else "uvx")
    venv_py = prefix / "venv" / ("Scripts" if _IS_WINDOWS else "bin") / (
        "python.exe" if _IS_WINDOWS else "python"
    )
    bin_dir = prefix / "bin"

    if isolated:
        add_to_path = True
        notes = ["--isolated: always adding bin/ to PATH"]
    else:
        add_to_path, notes = _path_decision(bin_dir)

    lines: list[str] = [
        f"# managed-python v{distro_version} -- generated by setup.py",
        "# Do not edit manually; re-run install to regenerate",
        "",
        "# Env vars (always set -- these are the reliable contract)",
        f'$env:{uv_env} = "{uv_exe}"',
        f'$env:{uvx_env} = "{uvx_exe}"',
        f'$env:{python_env} = "{venv_py}"',
    ]
    if _IS_WINDOWS:
        lines.append('$env:PYTHONUTF8 = "1"')
    lines.append("")

    if add_to_path:
        lines += [f"# {n}" for n in notes]
        lines.append(f'$env:PATH = "{bin_dir};" + $env:PATH')
    else:
        lines += [f"# {n}" for n in notes]
        lines.append(f'# $env:PATH = "{bin_dir};" + $env:PATH')

    (prefix / "env.ps1").write_text("\n".join(lines) + "\n", encoding="utf-8")
    _ok("env.ps1")


# ── env.bat ───────────────────────────────────────────────────────────────────

def _write_env_bat(prefix: Path, uv_env: str, uvx_env: str, python_env: str, distro_version: str, *, isolated: bool = False) -> None:
    if not _IS_WINDOWS:
        return

    uv_exe  = prefix / "uv.exe"
    uvx_exe = prefix / "uvx.exe"
    venv_py = prefix / "venv" / "Scripts" / "python.exe"
    bin_dir = prefix / "bin"

    if isolated:
        add_to_path = True
        notes = ["--isolated: always adding bin/ to PATH"]
    else:
        add_to_path, notes = _path_decision(bin_dir)

    lines: list[str] = [
        f"@echo off",
        f":: managed-python v{distro_version} -- generated by setup.py",
        ":: Do not edit manually; re-run install to regenerate",
        "",
        ":: Env vars (always set -- these are the reliable contract)",
        f'SET {uv_env}={uv_exe}',
        f'SET {uvx_env}={uvx_exe}',
        f'SET {python_env}={venv_py}',
        'SET PYTHONUTF8=1',
        "",
    ]

    if add_to_path:
        lines += [f":: {n}" for n in notes]
        lines.append(f'SET PATH={bin_dir};%PATH%')
    else:
        lines += [f":: {n}" for n in notes]

    (prefix / "env.bat").write_text("\r\n".join(lines) + "\r\n", encoding="utf-8")
    _ok("env.bat")


# ── distro.toml ───────────────────────────────────────────────────────────────

def _write_installed_distro_toml(
    script_dir: Path,
    prefix: Path,
    min_python: str,
    uv_env: str,
    uvx_env: str,
    python_env: str,
    shell_profile: bool,
    isolated: bool = False,
) -> None:
    """
    Write distro.toml to the prefix, appending an [install] section that
    records the options used. Enables inspection and replay of the install.
    """
    source = (script_dir / "distro.toml").read_text(encoding="utf-8").rstrip()
    install_section = (
        f"\n\n[install]\n"
        f'prefix       = "{prefix.as_posix()}"\n'
        f'python       = "{min_python}"\n'
        f'uv_env       = "{uv_env}"\n'
        f'uvx_env      = "{uvx_env}"\n'
        f'python_env   = "{python_env}"\n'
        f"shell_profile = {'true' if shell_profile else 'false'}\n"
        f"isolated      = {'true' if isolated else 'false'}\n"
    )
    (prefix / "distro.toml").write_text(source + install_section, encoding="utf-8")


# ── Shell profile ─────────────────────────────────────────────────────────────

def _update_shell_profile(prefix: Path) -> None:
    _step("Updating shell profile")

    if _IS_WINDOWS:
        env_ps1 = prefix / "env.ps1"
        _info(f'Add to your PowerShell profile:  . "{env_ps1}"')
        return

    env_sh      = prefix / "env.sh"
    source_line = f'source "{env_sh}"'

    shell = os.environ.get("SHELL", "")
    if "zsh" in shell:
        rc = Path.home() / ".zshrc"
    elif "bash" in shell:
        rc = Path.home() / ".bashrc"
    elif (Path.home() / ".zshrc").exists():
        rc = Path.home() / ".zshrc"
    elif (Path.home() / ".bashrc").exists():
        rc = Path.home() / ".bashrc"
    else:
        _warn(f'Could not detect shell rc. Add manually:  source "{env_sh}"')
        return

    existing = rc.read_text(encoding="utf-8") if rc.exists() else ""
    if source_line in existing:
        _ok(f"Shell profile already configured: {rc}")
        return

    with rc.open("a", encoding="utf-8") as fh:
        fh.write(f"\n# managed-python\n{source_line}\n")
    _ok(f"Appended to {rc}")
    _info(f'Restart your shell or run:  source "{env_sh}"')


# ── Main ──────────────────────────────────────────────────────────────────────

def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Post-bootstrap configuration for managed-python (stdlib, no deps).",
    )
    p.add_argument("--prefix",       required=True,                help="Install prefix")
    p.add_argument("--python",       required=True, dest="python_version")
    p.add_argument("--uv-env",       required=True, dest="uv_env",     help="Env var name for uv path")
    p.add_argument("--uvx-env",      required=True, dest="uvx_env",    help="Env var name for uvx path")
    p.add_argument("--python-env",   required=True, dest="python_env", help="Env var name for python path")
    p.add_argument("--shell-profile", action="store_true", dest="shell_profile")
    p.add_argument("--isolated",     action="store_true", dest="isolated")
    p.add_argument("--quiet", "-q", action="store_true", dest="quiet",
                   help="Suppress all output except warnings")
    return p.parse_args()


def main() -> None:
    global _QUIET
    args       = _parse_args()
    _QUIET     = args.quiet
    prefix     = Path(args.prefix).expanduser().resolve()
    script_dir = Path(__file__).parent.resolve()

    distro_version = _toml_get(script_dir / "distro.toml", "version")

    _create_bin(prefix)
    _write_env_sh(prefix, args.uv_env, args.uvx_env, args.python_env, distro_version, isolated=args.isolated)
    _write_env_ps1(prefix, args.uv_env, args.uvx_env, args.python_env, distro_version, isolated=args.isolated)
    _write_env_bat(prefix, args.uv_env, args.uvx_env, args.python_env, distro_version, isolated=args.isolated)
    _write_installed_distro_toml(
        script_dir, prefix, args.python_version, args.uv_env, args.uvx_env, args.python_env, args.shell_profile,
        isolated=args.isolated,
    )

    if args.shell_profile:
        _update_shell_profile(prefix)

    if not _QUIET:
        print()
        _banner("Install complete!")
        print()
        if _IS_WINDOWS:
            print(f'  . "{prefix / "env.ps1"}"')
            print(f'  or (PowerShell, if scripts are restricted):')
            print(f'    Invoke-Expression (Get-Content "{prefix / "env.ps1"}" -Raw)')
            print(f'  or (CMD):  call "{prefix / "env.bat"}"')
        else:
            print(f'  source "{prefix / "env.sh"}"')
        print()
        if _IS_WINDOWS:
            print(f'  Then:  $env:{args.python_env} /path/to/script.py')
            print(f'         $env:{args.uv_env} run --project /path/to/app script.py')
            print(f'         $env:{args.uvx_env} ruff --version')
        else:
            print(f'  Then:  "${args.python_env}" /path/to/script.py')
            print(f'         "${args.uv_env}" run --project /path/to/app script.py')
            print(f'         "${args.uvx_env}" ruff --version')
        print()


if __name__ == "__main__":
    main()
