#!/usr/bin/env bash
set -uo pipefail

export NO_UPDATE_NOTIFIER=1
problems=()
warnings=()

for command_name in node npm playwright-cli; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        problems+=("$command_name is not installed or is not on PATH.")
    fi
done

if command -v node >/dev/null 2>&1; then
    node_version="$(node --version)"
    node_major="${node_version#v}"
    node_major="${node_major%%.*}"
    if [[ ! "$node_major" =~ ^[0-9]+$ ]] || (( node_major < 20 )); then
        problems+=("Node.js $node_version is too old; the current Playwright runtime requires Node.js 20 or newer.")
    else
        printf 'Node.js: %s (%s)\n' "$node_version" "$(command -v node)"
    fi
fi

is_wsl=false
if [[ -n "${WSL_DISTRO_NAME:-}" || -e /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
    is_wsl=true
fi

if command -v playwright-cli >/dev/null 2>&1; then
    cli_path="$(command -v playwright-cli)"
    if [[ "$is_wsl" == true && "$cli_path" == /mnt/* ]]; then
        problems+=("WSL resolved the Windows playwright-cli shim at '$cli_path'. Install Node.js and @playwright/cli inside WSL and put that bin directory before /mnt paths.")
    elif cli_version="$(playwright-cli --version)"; then
        printf 'playwright-cli: %s (%s)\n' "$cli_version" "$cli_path"
    else
        problems+=("playwright-cli --version failed.")
    fi
fi

if [[ "${NODE_TLS_REJECT_UNAUTHORIZED:-}" == 0 ]]; then
    warnings+=("NODE_TLS_REJECT_UNAUTHORIZED=0 disables TLS certificate verification. Configure the corporate CA instead.")
fi

available_kib="$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 { print $4 }')"
if [[ "$available_kib" =~ ^[0-9]+$ ]] && (( available_kib < 1048576 )); then
    warnings+=("Less than 1 GiB is free on the filesystem containing HOME; Node or browser installation may fail.")
fi

for warning in "${warnings[@]}"; do
    printf 'WARNING: %s\n' "$warning" >&2
done
if (( ${#problems[@]} > 0 )); then
    for problem in "${problems[@]}"; do
        printf 'ERROR: %s\n' "$problem" >&2
    done
    exit 1
fi

echo "playwright-cli environment checks passed."
