---
name: shellcheck
description: "Lint shell scripts with shellcheck, fix warnings, and validate correctness"
---

# ShellCheck Linting Skill

Lint deliverable `.sh` and `.bash` files using `shellcheck`. Fix all actionable warnings.

## Scope

**Lint these** — any shell script that persists as a project artifact:
- Scripts committed to the repo
- Shell templates (`.sh.template`)
- Generated scripts users will run (e.g., `ralph.sh`)

**Skip these** — ephemeral scripts used during task execution:
- Inline `bash` tool one-liners
- Ad-hoc pipeline glue
- Throwaway diagnostic commands

## Prerequisites

```bash
pip install shellcheck-py   # preferred — no sudo needed
```

## Workflow

1. **Run shellcheck** with machine-parseable output:
   ```bash
   shellcheck -f gcc <file>
   ```

2. **Fix** each warning:

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

3. **Re-run shellcheck** after fixes — must be clean before reporting done.

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

- **Line-level**: `# shellcheck disable=SC2034` on the line before
- **File-level**: `# shellcheck disable=SC2129` after the shebang
- **Never suppress** SC2086 or SC2046 without a clear reason
- Always comment WHY when suppressing

## Useful Flags

```bash
shellcheck -x script.sh          # follow sourced files
shellcheck -s bash script.sh     # force bash dialect
shellcheck -e SC1090 script.sh   # exclude specific codes
shellcheck -f diff script.sh     # output as unified diff
```
