#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 [--uninstall] [--copilot|--codex|--all] [--skills-dir DIR]"
    echo ""
    echo "Install all skills:    $0                        # defaults to ~/.copilot/skills and ~/.codex/skills"
    echo "Copilot only:          $0 --copilot"
    echo "Codex only:            $0 --codex"
    echo "Custom dir:            $0 --skills-dir .github/skills"
    echo "Back-compat custom:    $0 /path/to/skills"
    echo "Uninstall all skills:  $0 --uninstall"
    echo ""
    echo "Installs: circuit-sim, elmer-fem, netlist-to-schematic, memory"
    exit 1
}

UNINSTALL=false
INSTALL_COPILOT=false
INSTALL_CODEX=false
SAW_TARGET_FLAG=false
SKILLS_DIR=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --uninstall) UNINSTALL=true ;;
        --copilot)
            INSTALL_COPILOT=true
            SAW_TARGET_FLAG=true
            ;;
        --codex)
            INSTALL_CODEX=true
            SAW_TARGET_FLAG=true
            ;;
        --all)
            INSTALL_COPILOT=true
            INSTALL_CODEX=true
            SAW_TARGET_FLAG=true
            ;;
        --skills-dir)
            shift
            [ "$#" -gt 0 ] || { echo "Missing value for --skills-dir" >&2; exit 1; }
            SKILLS_DIR="$1"
            ;;
        --skills-dir=*)
            SKILLS_DIR="${1#*=}"
            ;;
        -h|--help) usage ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
        *)
            [ -z "$SKILLS_DIR" ] || { echo "Only one skills directory may be specified" >&2; exit 1; }
            SKILLS_DIR="$1"
            ;;
    esac
    shift
done

if [ -n "$SKILLS_DIR" ] && [ "$SAW_TARGET_FLAG" = true ]; then
    echo "Use either --skills-dir or agent flags, not both." >&2
    exit 1
fi

PASSTHRU=()
if [ -n "$SKILLS_DIR" ]; then
    PASSTHRU=(--skills-dir "$SKILLS_DIR")
else
    if [ "$INSTALL_COPILOT" = false ] && [ "$INSTALL_CODEX" = false ]; then
        PASSTHRU=(--all)
    else
        [ "$INSTALL_COPILOT" = true ] && PASSTHRU+=(--copilot)
        [ "$INSTALL_CODEX" = true ] && PASSTHRU+=(--codex)
    fi
fi

[ "$UNINSTALL" = true ] && PASSTHRU=(--uninstall "${PASSTHRU[@]}")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for skill_dir in "$SCRIPT_DIR"/skills/*/; do
    skill_install="$skill_dir/install.sh"
    if [ -x "$skill_install" ]; then
        "$skill_install" "${PASSTHRU[@]}"
    fi
done
