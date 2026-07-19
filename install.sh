#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 [--uninstall] [--copilot|--codex|--all] [--skills-dir DIR] [options]"
    echo ""
    echo "Install all:        $0"
    echo "Copilot only:       $0 --copilot"
    echo "Codex only:         $0 --codex"
    echo "Custom skills dir:  $0 --skills-dir .github/skills"
    echo "Back-compat custom: $0 /path/to/skills"
    echo "Uninstall all:      $0 --uninstall"
    echo ""
    echo "Options:"
    echo "  --no-profiles             Skip build123d profile files"
    echo "  --install-shell-aliases   Install codex-build123d and copilot-build123d helpers into ~/.bashrc"
    echo "  --smoke-test-build123d    Run build123d-mcp --version through uv"
    echo ""
    echo "Installs skills: circuit-sim, commit, elmer-fem, expo-firebase-stack,"
    echo "                 mermaid, memory, netlist-to-schematic, playwright-cli,"
    echo "                 robust-doc, shellcheck, technical-report, uv"
    echo "Installs profile: build123d"
    exit 1
}

UNINSTALL=false
INSTALL_COPILOT=false
INSTALL_CODEX=false
SAW_TARGET_FLAG=false
SKILLS_DIR=""
NO_PROFILES=false
INSTALL_SHELL_ALIASES=false
SMOKE_TEST_BUILD123D=false

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
        --no-profiles) NO_PROFILES=true ;;
        --install-shell-aliases) INSTALL_SHELL_ALIASES=true ;;
        --smoke-test-build123d) SMOKE_TEST_BUILD123D=true ;;
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

agent_target() {
    if [ "$INSTALL_COPILOT" = true ] && [ "$INSTALL_CODEX" = false ]; then
        echo "copilot"
    elif [ "$INSTALL_CODEX" = true ] && [ "$INSTALL_COPILOT" = false ]; then
        echo "codex"
    else
        echo "all"
    fi
}

require_uv() {
    command -v uv >/dev/null 2>&1 || {
        echo "uv is required for build123d profile setup." >&2
        exit 1
    }
}

install_build123d_profile() {
    require_uv
    local target
    target="$(agent_target)"
    local args=(run --upgrade --python 3.12 "$SCRIPT_DIR/scripts/install_build123d_profile.py" --target "$target")
    if [ "$UNINSTALL" = true ]; then
        args+=(--uninstall)
    fi
    uv "${args[@]}"
}

smoke_test_build123d() {
    require_uv
    uv tool run --python 3.12 --from "git+https://github.com/pzfreo/build123d-mcp@main" build123d-mcp --version
}

strip_alias_block() {
    local profile="$1"
    local tmp
    tmp="$(mktemp)"
    if [ -f "$profile" ]; then
        awk '
            /^# >>> agent-skills build123d aliases >>>$/ { skip = 1; next }
            /^# <<< agent-skills build123d aliases <<<$/ { skip = 0; next }
            !skip { print }
        ' "$profile" > "$tmp"
    else
        : > "$tmp"
    fi
    cat "$tmp" > "$profile"
    rm -f "$tmp"
}

install_shell_aliases() {
    local source="$SCRIPT_DIR/profiles/build123d/aliases/agent-modes.sh"
    local target_dir="$HOME/.codex/shell"
    local target="$target_dir/agent-modes.sh"
    local profile="$HOME/.bashrc"

    mkdir -p "$target_dir"
    cp "$source" "$target"
    touch "$profile"
    strip_alias_block "$profile"
    {
        printf '\n# >>> agent-skills build123d aliases >>>\n'
        printf '. "%s"\n' "$target"
        printf '# <<< agent-skills build123d aliases <<<\n'
    } >> "$profile"
    echo "Installed shell launch helpers to $target"
    echo "Updated shell profile $profile"
}

uninstall_shell_aliases() {
    local target="$HOME/.codex/shell/agent-modes.sh"
    local profile="$HOME/.bashrc"

    if [ -f "$target" ]; then
        rm -f "$target"
        echo "Removed shell launch helpers from $target"
    fi
    if [ -f "$profile" ]; then
        strip_alias_block "$profile"
        echo "Removed build123d alias block from $profile"
    fi
}

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

for skill_dir in "$SCRIPT_DIR"/skills/*/; do
    skill_install="$skill_dir/install.sh"
    if [ -x "$skill_install" ]; then
        "$skill_install" "${PASSTHRU[@]}"
    fi
done

if [ -z "$SKILLS_DIR" ] && [ "$UNINSTALL" = false ]; then
    install_copilot_instr=false
    install_codex_instr=false

    if [ "$INSTALL_COPILOT" = true ] || { [ "$INSTALL_COPILOT" = false ] && [ "$INSTALL_CODEX" = false ]; }; then
        install_copilot_instr=true
    fi
    if [ "$INSTALL_CODEX" = true ] || { [ "$INSTALL_COPILOT" = false ] && [ "$INSTALL_CODEX" = false ]; }; then
        install_codex_instr=true
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
fi

if [ -z "$SKILLS_DIR" ] && [ "$NO_PROFILES" = false ]; then
    install_build123d_profile
fi

if [ -z "$SKILLS_DIR" ] && [ "$INSTALL_SHELL_ALIASES" = true ]; then
    if [ "$UNINSTALL" = true ]; then
        uninstall_shell_aliases
    else
        install_shell_aliases
    fi
fi

if [ -z "$SKILLS_DIR" ] && [ "$SMOKE_TEST_BUILD123D" = true ] && [ "$UNINSTALL" = false ]; then
    smoke_test_build123d
fi
