---
name: shellcheck
description: "Lint shell scripts with ShellCheck and PowerShell scripts with PSScriptAnalyzer"
---

# Script Linting Skill

Lint deliverable shell scripts with the right analyzer. ShellCheck does **not**
lint PowerShell; use PSScriptAnalyzer for PowerShell scripts.

## Scope

| Files | Tool |
|-------|------|
| `.sh`, `.bash`, `.sh.template` | `shellcheck` |
| `.ps1`, `.psm1`, `.psd1` | `PSScriptAnalyzer` |

**Skip these** — ephemeral scripts used during task execution:
- Inline `bash`/`pwsh` tool one-liners
- Ad-hoc pipeline glue
- Throwaway diagnostic commands

## Prerequisites

```bash
pip install shellcheck-py   # ShellCheck, no sudo needed
```

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
```

PSScriptAnalyzer is the PowerShell equivalent and a separate module; it is not
bundled with PowerShell.

## Shell Scripts

```bash
shellcheck -f gcc <file>
```

Fix each warning:

| Code | Issue | Fix |
|------|-------|-----|
| SC1090 | Can't follow non-constant source | `# shellcheck source=/dev/null` before the `source` line |
| SC1091 | Not following sourced file | Same as SC1090, or `# shellcheck source=path/to/file` |
| SC2034 | Variable appears unused | Remove, export, or `# shellcheck disable=SC2034` with explanation |
| SC2043 | Loop will only run once | Replace `for var in SINGLE; do` with direct check |
| SC2086 | Double-quote to prevent globbing | `"$var"` instead of `$var` |
| SC2129 | Use grouped redirects | `{ cmd1; cmd2; } >> file` |
| SC2012 | Use find instead of ls | `find dir -name '*.ext' \| wc -l` |
| SC1083 | Literal `{` or `}` | Quote it — or it signals a template placeholder bug |
| SC2155 | Declare and assign separately | `local var; var=$(cmd)` |
| SC2164 | Use `cd ... \|\| exit` | `cd dir || exit 1` |

Re-run ShellCheck after fixes. Results must be clean before reporting done.

## PowerShell Scripts

```powershell
Invoke-ScriptAnalyzer -Path .\script.ps1
Invoke-ScriptAnalyzer -Path . -Recurse
Invoke-ScriptAnalyzer -Path .\script.ps1 -Fix
```

Use `-Fix` only when the change is safe, then review the diff. Fix all
diagnostics and re-run PSScriptAnalyzer. Results must be clean before reporting
done.

## Template Files

Shell templates (e.g., `*.sh.template`) use `@@PLACEHOLDER@@` for generation-time
substitution and `__NAME__` for runtime substitution. These conventions are chosen
to avoid colliding with bash `${}` syntax.

- shellcheck may flag `@@PLACEHOLDER@@` as syntax errors — this is expected
- Verify the template is clean by running shellcheck on a **generated instance**
  (after substitution) rather than suppressing warnings on the template itself
- SC1083 ("literal `{`") in a shell script is a red flag — it may indicate
  someone used `{NAME}` placeholders instead of `@@NAME@@`

## Severity Triage

- **error**: Always fix
- **warning**: Almost always fix
- **info/style**: Fix if trivial; suppress at file level if intentional

## Suppression Rules

Prefer fixing over suppressing. Suppress narrowly only when the diagnostic is
intentional and documented.

**ShellCheck**

- **Line-level**: `# shellcheck disable=SC2034` on the line before
- **File-level**: `# shellcheck disable=SC2129` after the shebang
- **Never suppress** SC2086 or SC2046 without a clear reason
- Always comment WHY when suppressing

**PSScriptAnalyzer**

Use `SuppressMessageAttribute` with a justification:

```powershell
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Justification = 'Interactive script intentionally writes host output.'
)]
param()
```

## Useful Flags

```bash
shellcheck -x script.sh          # follow sourced files
shellcheck -s bash script.sh     # force bash dialect
shellcheck -e SC1090 script.sh   # exclude specific codes
shellcheck -f diff script.sh     # output as unified diff
```

```powershell
Invoke-ScriptAnalyzer -Path .\script.ps1
Invoke-ScriptAnalyzer -Path . -Recurse
Invoke-ScriptAnalyzer -Path .\script.ps1 -Fix
```
