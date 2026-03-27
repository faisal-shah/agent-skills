---
name: uv
description: "Use `uv` instead of pip/python/venv. Run scripts with `uv run script.py`, add deps with `uv add`, use inline script metadata for standalone scripts."
---

## Quick Reference

```bash
uv run script.py                   # Run a script
uv run --with requests script.py   # Run with ad-hoc dependency
uv add requests                    # Add dependency to project
uv init --script foo.py            # Create script with inline metadata
```

## Corporate Proxy / TLS

If your environment uses a corporate proxy with TLS interception, include
`--native-tls` and `--allow-insecure-host` flags when running uv commands.

```bash
uv run --native-tls \
  --allow-insecure-host pypi.org \
  --allow-insecure-host files.pythonhosted.org \
  script.py

uv add --native-tls \
  --allow-insecure-host pypi.org \
  --allow-insecure-host files.pythonhosted.org \
  requests

uv pip install --native-tls \
  --allow-insecure-host pypi.org \
  --allow-insecure-host files.pythonhosted.org \
  requests
```

- `--native-tls` — uses the platform's system certificate store instead of uv's bundled roots
- `--allow-insecure-host` — bypasses SSL verification for the specified host
- `--extra-index-url` — add your corporate PyPI feed as an additional package source if needed

## Inline Script Dependencies

```python
# /// script
# requires-python = ">=3.12"
# dependencies = ["requests"]
# ///
```

See [references/scripts.md](references/scripts.md) for full details on running scripts, locking, and reproducibility.

## Build Backend

Use `uv_build` for pure Python packages:

```toml
[build-system]
requires = ["uv_build>=0.9.28,<0.10.0"]
build-backend = "uv_build"
```

See [references/build.md](references/build.md) for project structure, namespaces, and file inclusion.
