#!/usr/bin/env bash

codex-build123d() {
    codex --profile build123d "$@"
}

copilot-build123d() {
    copilot --agent build123d "$@"
}

# Open the build123d live 3D viewer for a running agent's MCP session.
# Usage: build123d-viewer [socket_path]
#   With no path, connects to the newest /tmp/build123d-mcp.*.sock (right when a
#   single agent is running). When several agents run at once, ask the agent for
#   its viewer socket path and pass it explicitly.
build123d-viewer() {
    local script=""
    local candidate
    for candidate in "$HOME/.copilot/profiles/build123d/viewer/live_viewer_pyvista.py" \
                     "$HOME/.codex/profiles/build123d/viewer/live_viewer_pyvista.py"; do
        if [ -f "$candidate" ]; then
            script="$candidate"
            break
        fi
    done
    if [ -z "$script" ]; then
        echo "build123d viewer not installed; run the agent-skills installer first." >&2
        return 1
    fi
    uv run --python 3.12 "$script" "$@"
}
