# AGENTS.md — AI Context for shellcheck skill

## What This Skill Is

Guidelines for linting shell scripts with `shellcheck`. The agent reads this
to know which files to lint, how to fix common warnings, when to suppress,
and how to handle template files with placeholders.

## Key Files

- `SKILL.md` — Scope rules, common warning fixes, suppression guidelines,
  template file handling, and useful flags

## Design Principles

1. **Lint deliverables, skip ephemera.** Committed scripts and templates
   get linted; throwaway one-liners don't.
2. **Fix, don't suppress.** Suppress only when intentional, always with a comment.
3. **Template awareness.** `@@PLACEHOLDER@@` and `__NAME__` conventions avoid
   colliding with bash `${}` syntax.
4. **Machine-parseable output.** Always use `-f gcc` format for programmatic
   consumption.
5. **Zero warnings.** The goal is a clean shellcheck run, not "mostly clean".

## Testing Changes

```bash
# Create a test script with a known warning and verify shellcheck catches it
echo '#!/bin/bash\necho $UNQUOTED' > /tmp/test-sc.sh
shellcheck -f gcc /tmp/test-sc.sh
rm /tmp/test-sc.sh
```

## Style

- SKILL.md: table-driven for warning codes. No prose for things a table can say.
- Keep the common-warnings table updated as new patterns are encountered.
