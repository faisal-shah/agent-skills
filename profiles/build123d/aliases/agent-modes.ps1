function Invoke-CodexBuild123d {
    codex --profile build123d @args
}

function Invoke-CopilotBuild123d {
    copilot --agent build123d @args
}

Set-Alias -Name codex-build123d -Value Invoke-CodexBuild123d
Set-Alias -Name copilot-build123d -Value Invoke-CopilotBuild123d
