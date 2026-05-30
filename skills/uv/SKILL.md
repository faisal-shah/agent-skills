---
name: uv
description: "Use `uv` for Python execution, dependencies, standalone PEP 723 scripts, and packaging. Prefer `uv run`, `uv add`, and inline script metadata over ad-hoc pip/venv workflows."
---

# uv Skill

Use this skill whenever an agent needs to run Python, create a one-off script,
add dependencies, test a Python project, or build a package. Optimize for
reproducible commands the next agent can rerun.

## Decision Flow

1. **Standalone script or generated artifact?** Use a PEP 723 script and run it
   with `uv run script.py`.
2. **Existing project?** Stay inside the project: `uv run ...`, `uv add ...`,
   `uv lock --check`.
3. **One command needs a temporary dependency?** Use `uv run --with package ...`;
   do not mutate the project.
4. **Import works in system Python but fails under `uv run`?** Treat it as uv
   isolation: declare the dependency, pass `--with`, set `PYTHONPATH`, or expose
   the private index.
5. **Windows/corporate network?** Add the TLS flags before assuming dependency
   resolution is broken.

## Command Recipes

```bash
# Run scripts
uv run script.py
uv run --with requests script.py
uv run --no-project script.py

# Create and maintain standalone scripts
uv init --script report.py --python 3.12
uv add --script report.py python-docx matplotlib
uv lock --script report.py

# Project dependencies and validation
uv add requests
uv run pytest -q
uv lock --check

# Build packages
uv build
uv run --with build python -m build   # only when the repo requires `build`
```

Prefer `uv run --with ...` for transient tools. Use `uv add ...` only when the
project itself needs the dependency.

## Standalone Script Contract

For generated scripts, put the contract in the file before the first run:

```python
# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "requests<3",
#   "rich",
# ]
# ///
```

Agent checklist:

1. Include every non-stdlib import in the metadata.
2. Smoke-test immediately: `uv run script.py --help` or a tiny real input.
3. If the output matters, save the script beside the artifact, not only in
   `/tmp`.
4. If multiple scripts share heavy deps, consolidate or reuse one script to
   avoid repeated resolver/install output.

See [references/scripts.md](references/scripts.md) for script locking,
shebangs, alternative indexes, and reproducibility.

## Windows / Corporate TLS

If your environment uses a corporate proxy with TLS interception, include
`--native-tls` and `--allow-insecure-host` on dependency-resolving commands.

```powershell
uv run --python 3.12 --native-tls `
  --allow-insecure-host pypi.org `
  --allow-insecure-host files.pythonhosted.org `
  script.py

uv add --native-tls `
  --allow-insecure-host pypi.org `
  --allow-insecure-host files.pythonhosted.org `
  requests

uv pip install --native-tls `
  --allow-insecure-host pypi.org `
  --allow-insecure-host files.pythonhosted.org `
  requests
```

```bash
uv run --python 3.12 --native-tls \
  --allow-insecure-host pypi.org \
  --allow-insecure-host files.pythonhosted.org \
  script.py
```

Use the same flags for PEP 723 scripts that pull `python-docx`, plotting,
Playwright, or other report-generation dependencies.

## Private Indexes and uv Isolation

`uv run` is isolated. If `python3` can import a package but `uv run` cannot, do
not assume uv is broken; the package is outside uv's environment.

```bash
# Temporary public dependency
uv run --with scipy script.py

# Local source checkout needed by the script
PYTHONPATH="$PWD" uv run --with pytest pytest tests/test_feature.py -q

# Private package feed already configured for pip
UV_EXTRA_INDEX_URL="$(pip config get global.extra-index-url 2>/dev/null)" \
  uv run --with private-package script.py
```

For wrappers, resolve `UV_EXTRA_INDEX_URL` once and pass it through to all
`uv run` calls. Add error messages that say "run through uv" when bypassing
`uv run` would bypass PEP 723 dependency installation and PATH exposure.

## Build Backend and Builds

Use `uv_build` for pure Python packages:

```toml
[build-system]
requires = ["uv_build>=0.9.28,<0.10.0"]
build-backend = "uv_build"
```

Default package layout:

```text
pyproject.toml
src/
  my_package/
    __init__.py
```

Important build rules:

- Prefer `uv build` for uv-managed packages.
- `uv run python -m build` requires `build` in the uv environment; use
  `uv run --with build python -m build` only when that workflow is required.
- `uv_build` normalizes project names (`solidworks-compare` ->
  `solidworks_compare`). If the import module differs, configure it explicitly:

```toml
[tool.uv.build-backend]
module-name = "actual_import_module"
```

See [references/build.md](references/build.md) for namespace packages and file
inclusion/exclusion.

## Tool-Call Hygiene

- Start with focused commands; run full suites only after targeted validation.
- Put long-running full suites behind a timeout, e.g. `timeout 360s uv run ...`.
- Trim successful output with `-q`, `tail`, or logs; preserve full output only
  when debugging a failure.
- For GUI smoke tests, set display-safe env vars before `uv run`, e.g.
  `QT_QPA_PLATFORM=offscreen` and `XDG_RUNTIME_DIR=/tmp/...`.
- On Windows text extraction/reporting commands, set `PYTHONIOENCODING=utf-8`
  before printing document contents.

## Common Failure Patterns

| Symptom | Response |
|---|---|
| `ModuleNotFoundError` only under `uv run` | Add PEP 723 dependency, use `--with`, set `PYTHONPATH`, or expose private index. |
| Resolver stalls or TLS/certificate errors on Windows | Retry with `--native-tls` and both PyPI insecure-host flags. |
| `uv run python -m build` fails | Use `uv build` or add `--with build`. |
| `uv_build` packages the wrong module | Check normalized project name; set `[tool.uv.build-backend].module-name`. |
| Huge install output swamps the tool result | Use one consolidated script or quiet/targeted validation; inspect logs only on failure. |
