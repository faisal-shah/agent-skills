# AGENTS.md — AI Context for uv skill

## What This Skill Is

A quick-reference guide for using `uv` as the primary Python tool — replacing
pip, python, venv, and pip-tools. Covers running scripts, managing dependencies,
inline script metadata (PEP 723), and the `uv_build` build backend.

## Key Files

- `SKILL.md` — Quick reference, proxy/TLS notes, inline metadata, build backend
- `references/scripts.md` — Full guide to running scripts with uv (ad-hoc deps,
  locking, reproducibility, shebang)
- `references/build.md` — `uv_build` backend setup, project structure, namespaces,
  file inclusion/exclusion

## Design Principles

1. **Replace pip everywhere.** `uv run`, `uv add`, `uv pip install` — never
   bare `pip` or `python -m pip`.
2. **PEP 723 inline metadata.** Standalone scripts declare their own dependencies
   in `# /// script` blocks — no separate requirements.txt.
3. **Corporate-friendly.** The proxy/TLS section exists because many corporate
   environments need `--native-tls` and `--allow-insecure-host`.
4. **Reference files for depth.** SKILL.md is a quick lookup; deep topics go in
   `references/`.

## Testing Changes

```bash
# Verify the skill installs cleanly with references
./skills/uv/install.sh --skills-dir /tmp/skills-test
ls /tmp/skills-test/uv/
ls /tmp/skills-test/uv/references/
# Should contain: SKILL.md, references/build.md, references/scripts.md
rm -rf /tmp/skills-test
```

## Style

- SKILL.md: code blocks over prose. Command → result format.
- References: one topic per file, progressively detailed.
