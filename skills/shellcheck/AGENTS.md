# AGENTS.md — AI Context for shellcheck skill

## What This Skill Is

Guidelines for linting shell scripts with ShellCheck and PowerShell scripts with
PSScriptAnalyzer. The agent reads this to know which files to lint, how to fix
common diagnostics, when to suppress, and how to handle template files with
placeholders.

## Key Files

- `SKILL.md` — Scope rules, analyzer workflows, common ShellCheck fixes,
  suppression guidelines, template file handling, and useful commands

## Design Principles

1. **Lint deliverables, skip ephemera.** Committed scripts and templates
   get linted; throwaway one-liners don't.
2. **Use the right analyzer.** ShellCheck handles `.sh`, `.bash`, and
   `.sh.template`; PSScriptAnalyzer handles `.ps1`, `.psm1`, and `.psd1`.
3. **Fix, don't suppress.** Suppress only when intentional, always with a
   justification.
4. **Template awareness.** `@@PLACEHOLDER@@` and `__NAME__` conventions avoid
   colliding with bash `${}` syntax.
5. **Machine-parseable shell output.** Use `shellcheck -f gcc` for ShellCheck
   diagnostics.
6. **Zero diagnostics.** The goal is a clean analyzer run, not "mostly clean".

## Testing Changes

```bash
# Create a test script with a known warning and verify shellcheck catches it
echo '#!/bin/bash\necho $UNQUOTED' > /tmp/test-sc.sh
shellcheck -f gcc /tmp/test-sc.sh
rm /tmp/test-sc.sh

# If pwsh and PSScriptAnalyzer are installed, verify a PowerShell issue
printf 'Write-Host "debug"\n' > /tmp/test-pssa.ps1
pwsh -NoProfile -Command 'Invoke-ScriptAnalyzer -Path /tmp/test-pssa.ps1'
rm /tmp/test-pssa.ps1
```

## Style

- SKILL.md: concise and table-driven. No prose for things a table can say.
- Keep ShellCheck warning tables and PSScriptAnalyzer command examples focused.
