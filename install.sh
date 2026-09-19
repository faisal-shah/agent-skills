#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 [--uninstall] [--copilot|--codex|--claude|--all] [--skills-dir DIR]"
    echo ""
    echo "Install all:        $0"
    echo "Copilot only:       $0 --copilot"
    echo "Codex only:         $0 --codex"
    echo "Claude Code only:   $0 --claude"
    echo "Custom skills dir:  $0 --skills-dir .github/skills"
    echo "Back-compat custom: $0 /path/to/skills"
    echo "Uninstall all:      $0 --uninstall"
    echo ""
    echo "Installs skills: circuit-sim, commit, elmer-fem, expo-firebase-stack,"
    echo "                 mermaid, memory, netlist-to-schematic, playwright-cli,"
    echo "                 robust-doc, shellcheck, technical-report, uv"
    exit 1
}

UNINSTALL=false
INSTALL_COPILOT=false
INSTALL_CODEX=false
INSTALL_CLAUDE=false
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
        --claude)
            INSTALL_CLAUDE=true
            SAW_TARGET_FLAG=true
            ;;
        --all)
            INSTALL_COPILOT=true
            INSTALL_CODEX=true
            INSTALL_CLAUDE=true
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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PASSTHRU=()
if [ -n "$SKILLS_DIR" ]; then
    PASSTHRU=(--skills-dir "$SKILLS_DIR")
else
    if [ "$SAW_TARGET_FLAG" = false ]; then
        PASSTHRU=(--copilot --codex)
    else
        [ "$INSTALL_COPILOT" = true ] && PASSTHRU+=(--copilot)
        [ "$INSTALL_CODEX" = true ] && PASSTHRU+=(--codex)
        [ "$INSTALL_CLAUDE" = true ] && PASSTHRU+=(--claude)
    fi
fi

[ "$UNINSTALL" = true ] && PASSTHRU=(--uninstall "${PASSTHRU[@]}")

for skill_dir in "$SCRIPT_DIR"/skills/*/; do
    # A skill can opt OUT of the bulk install by dropping a .no-default-install
    # marker in its directory. It is then installable only via its own
    # skills/<name>/install.sh. Used for project-specific skills (e.g.
    # sabeel-color-scheme) that most users of this repo do not want.
    if [ -f "$skill_dir/.no-default-install" ]; then
        continue
    fi
    skill_install="$skill_dir/install.sh"
    if [ -x "$skill_install" ]; then
        "$skill_install" "${PASSTHRU[@]}"
    fi
done

if [ -z "$SKILLS_DIR" ] && [ "$UNINSTALL" = false ]; then
    install_copilot_instr=false
    install_codex_instr=false
    install_claude_instr=false

    if [ "$INSTALL_COPILOT" = true ] || [ "$SAW_TARGET_FLAG" = false ]; then
        install_copilot_instr=true
    fi
    if [ "$INSTALL_CODEX" = true ] || [ "$SAW_TARGET_FLAG" = false ]; then
        install_codex_instr=true
    fi
    # Never by default: ~/.claude/CLAUDE.md is hand-edited far more often than the
    # other two, so it is only written when --claude is asked for explicitly.
    if [ "$INSTALL_CLAUDE" = true ]; then
        install_claude_instr=true
    fi

    if [ "$install_copilot_instr" = true ]; then
        mkdir -p "$HOME/.copilot"
        cp "$SCRIPT_DIR/copilot-instructions.md" "$HOME/.copilot/copilot-instructions.md"
        echo "Installed copilot-instructions.md to $HOME/.copilot/"
    fi
    if [ "$install_codex_instr" = true ]; then
        mkdir -p "$HOME/.codex"
        cp "$SCRIPT_DIR/codex-instructions.md" "$HOME/.codex/instructions.md"
        echo "Installed codex-instructions.md to $HOME/.codex/"
    fi
    if [ "$install_claude_instr" = true ]; then
        mkdir -p "$HOME/.claude"
        claude_target="$HOME/.claude/CLAUDE.md"
        if [ -f "$claude_target" ] && ! cmp -s "$SCRIPT_DIR/claude-instructions.md" "$claude_target"; then
            cp "$claude_target" "$claude_target.bak"
            echo "Backed up existing $claude_target to $claude_target.bak"
        fi
        cp "$SCRIPT_DIR/claude-instructions.md" "$claude_target"
        echo "Installed claude-instructions.md to $claude_target"
    fi
fi
