#!/usr/bin/env bash
set -euo pipefail

SKILL_NAME="memory"

usage() {
    echo "Usage: $0 [--uninstall] [--copilot|--codex|--all] [--skills-dir DIR]"
    echo ""
    echo "Install:    $0                            # defaults to ~/.copilot/skills and ~/.codex/skills"
    echo "Install:    $0 --copilot"
    echo "Install:    $0 --codex"
    echo "Install:    $0 --skills-dir .github/skills"
    echo "Install:    $0 /path/to/skills"
    echo "Uninstall:  $0 --uninstall               # removes from both default user dirs"
    echo ""
    echo "Creates <skills-directory>/$SKILL_NAME/ with SKILL.md."
    exit 1
}

UNINSTALL=false
INSTALL_COPILOT=false
INSTALL_CODEX=false
SAW_TARGET_FLAG=false
SKILLS_DIR=""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

install_to() {
    local skills_root="$1"
    local target="$skills_root/$SKILL_NAME"

    mkdir -p "$target"
    cp "$SCRIPT_DIR/SKILL.md" "$target/"
    echo "Installed $SKILL_NAME to $target"
}

remove_from() {
    local skills_root="$1"
    local target="$skills_root/$SKILL_NAME"

    if [ -d "$target" ]; then
        rm -rf "$target"
        echo "Removed $target"
    else
        echo "Nothing to remove: $target does not exist"
    fi
}

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

TARGET_DIRS=()
if [ -n "$SKILLS_DIR" ]; then
    TARGET_DIRS=("$SKILLS_DIR")
else
    if [ "$INSTALL_COPILOT" = false ] && [ "$INSTALL_CODEX" = false ]; then
        TARGET_DIRS=("$HOME/.copilot/skills" "$HOME/.codex/skills")
    else
        [ "$INSTALL_COPILOT" = true ] && TARGET_DIRS+=("$HOME/.copilot/skills")
        [ "$INSTALL_CODEX" = true ] && TARGET_DIRS+=("$HOME/.codex/skills")
    fi
fi

for skills_root in "${TARGET_DIRS[@]}"; do
    if [ "$UNINSTALL" = true ]; then
        remove_from "$skills_root"
    else
        install_to "$skills_root"
    fi
done
