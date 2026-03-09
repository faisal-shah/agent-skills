#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 [--uninstall] <skills-directory>"
    echo ""
    echo "Install all skills:    $0 ~/.copilot/skills"
    echo "Uninstall all skills:  $0 --uninstall ~/.copilot/skills"
    echo ""
    echo "Installs: circuit-sim, netlist-to-schematic, memory"
    exit 1
}

UNINSTALL=false
SKILLS_DIR=""

for arg in "$@"; do
    case "$arg" in
        --uninstall) UNINSTALL=true ;;
        -h|--help) usage ;;
        *) SKILLS_DIR="$arg" ;;
    esac
done

[ -z "$SKILLS_DIR" ] && usage

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for skill_dir in "$SCRIPT_DIR"/skills/*/; do
    skill_install="$skill_dir/install.sh"
    if [ -x "$skill_install" ]; then
        if [ "$UNINSTALL" = true ]; then
            "$skill_install" --uninstall "$SKILLS_DIR"
        else
            "$skill_install" "$SKILLS_DIR"
        fi
    fi
done
