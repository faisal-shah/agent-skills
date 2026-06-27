#!/usr/bin/env bash
# Validate Mermaid diagrams with the official Mermaid CLI (mmdc).
# Usage: validate.sh diagram.mmd|document.md [output.svg|output.png|output.pdf|output.md]

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: validate.sh INPUT [OUTPUT]

INPUT may be:
  diagram.mmd   Render a single Mermaid diagram.
  document.md   Extract Mermaid blocks, render artifacts, and rewrite Markdown.

OUTPUT may be .svg, .png, .pdf, or .md. If omitted, a temporary output is used
for validation and removed after the run.

Environment:
  MERMAID_PUPPETEER_CONFIG  Path to a Puppeteer JSON config for mmdc -p.
  PUPPETEER_EXECUTABLE_PATH Browser executable path used to create a temp config.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    usage
    exit 1
fi

INPUT="$1"
OUTPUT="${2:-}"

if [ ! -f "$INPUT" ]; then
    echo "Error: File not found: $INPUT" >&2
    exit 1
fi

case "${INPUT##*.}" in
    mmd|md) ;;
    *) echo "Warning: expected .mmd or .md input; mmdc will still try to render it." >&2 ;;
esac

TMP_DIR=""
CLEANUP=0
if [ -z "$OUTPUT" ]; then
    TMP_DIR=$(mktemp -d /tmp/mermaid_validate.XXXXXX)
    CLEANUP=1
    if [ "${INPUT##*.}" = "md" ]; then
        OUTPUT="$TMP_DIR/output.md"
    else
        OUTPUT="$TMP_DIR/output.svg"
    fi
fi

TMP_PUPPETEER_CONFIG=""
cleanup() {
    if [ -n "$TMP_PUPPETEER_CONFIG" ]; then
        rm -f "$TMP_PUPPETEER_CONFIG"
    fi
    if [ "$CLEANUP" -eq 1 ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

find_browser() {
    if [ -n "${PUPPETEER_EXECUTABLE_PATH:-}" ] && [ -x "$PUPPETEER_EXECUTABLE_PATH" ]; then
        printf '%s\n' "$PUPPETEER_EXECUTABLE_PATH"
        return 0
    fi

    local candidate
    for candidate in chromium chromium-browser google-chrome google-chrome-stable chrome microsoft-edge msedge; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done

    return 1
}

PUPPETEER_CONFIG="${MERMAID_PUPPETEER_CONFIG:-}"
if [ -z "$PUPPETEER_CONFIG" ]; then
    if BROWSER_PATH=$(find_browser); then
        TMP_PUPPETEER_CONFIG=$(mktemp /tmp/mermaid_puppeteer.XXXXXX.json)
        BROWSER_PATH="$BROWSER_PATH" python3 - <<'PYJSON' > "$TMP_PUPPETEER_CONFIG"
import json
import os
print(json.dumps({"executablePath": os.environ["BROWSER_PATH"]}))
PYJSON
        PUPPETEER_CONFIG="$TMP_PUPPETEER_CONFIG"
    fi
elif [ ! -f "$PUPPETEER_CONFIG" ]; then
    echo "Error: MERMAID_PUPPETEER_CONFIG does not exist: $PUPPETEER_CONFIG" >&2
    exit 1
fi

LOG=$(mktemp /tmp/mermaid_validate_log.XXXXXX)
trap 'rm -f "$LOG"; cleanup' EXIT

echo "Validating: $INPUT"

CMD=(npx -y @mermaid-js/mermaid-cli -i "$INPUT" -o "$OUTPUT" -q)
if [ -n "$PUPPETEER_CONFIG" ]; then
    CMD+=(-p "$PUPPETEER_CONFIG")
fi

if "${CMD[@]}" >"$LOG" 2>&1; then
    echo "✓ Mermaid OK"
    if [ "$CLEANUP" -eq 0 ]; then
        echo "Rendered to: $OUTPUT"
    fi
else
    cat "$LOG" >&2
    echo "✗ Mermaid validation failed" >&2
    if grep -qiE 'Could not find Chrome|Failed to launch the browser|Chrome.*not found|Chromium.*not found' "$LOG"; then
        cat >&2 <<'EOF'

Browser setup help:
- Install Chrome/Chromium and rerun, or set PUPPETEER_EXECUTABLE_PATH.
- Or create a Puppeteer config JSON and set MERMAID_PUPPETEER_CONFIG, e.g.:
    { "executablePath": "/usr/bin/chromium" }
- To install Puppeteer's browser cache, try:
    npx -y puppeteer browsers install chrome-headless-shell
EOF
    fi
    exit 1
fi
