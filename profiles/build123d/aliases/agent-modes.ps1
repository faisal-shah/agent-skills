function Invoke-CodexBuild123d {
    codex --profile build123d @args
}

function Invoke-CopilotBuild123d {
    copilot --agent build123d @args
}

# Claude Code has no --profile. The equivalent is a plugin directory loaded for
# this launch only: --plugin-dir brings the MCP server and the two workflow
# skills, --agent selects the profile instructions.
function Invoke-ClaudeBuild123d {
    claude --plugin-dir (Join-Path (Join-Path (Join-Path $HOME ".claude") "profiles") "build123d") --agent build123d @args
}

Set-Alias -Name codex-build123d -Value Invoke-CodexBuild123d
Set-Alias -Name copilot-build123d -Value Invoke-CopilotBuild123d
Set-Alias -Name claude-build123d -Value Invoke-ClaudeBuild123d
