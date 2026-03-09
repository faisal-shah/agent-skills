#!/usr/bin/env bash
set -euo pipefail

SKILL_NAME="circuit-sim"

usage() {
    echo "Usage: $0 [--uninstall] <skills-directory>"
    echo ""
    echo "Install:    $0 ~/.copilot/skills"
    echo "Uninstall:  $0 --uninstall ~/.copilot/skills"
    echo ""
    echo "Creates <skills-directory>/$SKILL_NAME/ with SKILL.md and scripts/."
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

TARGET="$SKILLS_DIR/$SKILL_NAME"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$UNINSTALL" = true ]; then
    if [ -d "$TARGET" ]; then
        rm -rf "$TARGET"
        echo "Removed $TARGET"
    else
        echo "Nothing to remove: $TARGET does not exist"
    fi
    exit 0
fi

mkdir -p "$TARGET/scripts"
cp "$SCRIPT_DIR/SKILL.md" "$TARGET/"
cp "$SCRIPT_DIR/scripts/"*.py "$TARGET/scripts/"
echo "Installed $SKILL_NAME to $TARGET"
