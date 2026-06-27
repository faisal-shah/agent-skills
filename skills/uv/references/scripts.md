# Running Scripts with uv

Use this reference when `SKILL.md` is not enough. The default agent pattern is:

1. create or edit a PEP 723 script;
2. declare every non-stdlib import;
3. smoke-run with `uv run`;
4. keep the script beside durable outputs.

## Basic Usage

```bash
uv run script.py                   # Run a script
uv run script.py arg1 arg2         # With arguments
uv run --python 3.10 script.py     # Specific Python version
echo 'print("hi")' | uv run -      # From stdin
```

In a project directory, use `--no-project` to skip installing the project:

```bash
uv run --no-project script.py
```

## Ad-hoc Dependencies

```bash
uv run --with requests script.py
uv run --with 'requests>2,<3' script.py
uv run --with requests --with rich script.py
```

## Inline Script Metadata (Recommended)

Declare dependencies directly in the script:

```python
# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "requests<3",
#   "rich",
# ]
# ///

import requests
from rich import print
```

Then just: `uv run script.py`

### Agent Checklist

- Put every import outside the standard library into `dependencies`.
- For local module imports, include transitive third-party dependencies used by
  those local modules too.
- Add version bounds when reproducibility matters.
- Run `uv run script.py --help` or the smallest real input immediately; do not
  rely on `py_compile` alone.
- Remove stale dependencies from the PEP 723 block after deleting features.
- Keep scripts that generate reports, figures, or engineering artifacts in a
  durable location with the output. Use `/tmp` only for disposable scratch.
- If multiple scripts share heavy packages such as `matplotlib`, `scipy`,
  `python-docx`, `pymupdf`, `gmsh`, or `playwright`, prefer one orchestrating
  script to repeated one-off resolver runs.

### Managing Dependencies

```bash
uv init --script example.py --python 3.12   # Create script with metadata
uv add --script example.py requests rich    # Add dependencies
```

### Alternative Index

```bash
uv add --index "https://example.com/simple" --script example.py requests
```

Adds to metadata:

```python
# [[tool.uv.index]]
# url = "https://example.com/simple"
```

For a private feed already configured for pip:

```bash
UV_EXTRA_INDEX_URL="$(pip config get global.extra-index-url 2>/dev/null)" \
  uv run --with private-package script.py
```

Wrappers should resolve this once and pass the environment through to nested
`uv run` calls.

### Windows Corporate TLS

When dependency resolution hits TLS/certificate errors on Windows, use:

```powershell
uv run --python 3.12 --native-tls `
  --allow-insecure-host pypi.org `
  --allow-insecure-host files.pythonhosted.org `
  script.py
```

Apply the same flags to `uv add` or `uv pip install` when those commands must
resolve packages.

## Locking Dependencies

```bash
uv lock --script example.py  # Creates example.py.lock
```

## Reproducibility

Pin resolution date:

```python
# /// script
# dependencies = ["requests"]
# [tool.uv]
# exclude-newer = "2023-10-16T00:00:00Z"
# ///
```

## Executable Scripts (Shebang)

```python
#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["httpx"]
# ///

import httpx
print(httpx.get("https://example.com"))
```

```bash
chmod +x myscript
./myscript
```

## Troubleshooting Script Runs

| Symptom | Fix |
|---|---|
| Import works with `python3` but not `uv run` | Add the package to PEP 723 metadata or use `uv run --with package ...`. |
| Local package checkout is needed | Prefix with `PYTHONPATH="$PWD"` or the exact `src` path. |
| Local helper imports a third-party package | Add that transitive dependency to the caller script metadata. |
| Private package cannot resolve | Export `UV_EXTRA_INDEX_URL` or add an inline index. |
| First run downloads large browser/GUI/science deps | Expect slow output; keep dependencies stable and avoid repeated script fragmentation. |
| Dataclass-heavy module imported dynamically from a PEP 723 script | Register the module in `sys.modules` before executing the imported module. |
