# uv Build Backend

Use `uv_build` for pure Python packages. For extension modules, use a backend
that explicitly supports compiled extensions, such as `hatchling` with the
project's existing extension tooling.

Default agent behavior:

1. Prefer the repository's existing packaging convention.
2. Use `uv build` for uv-managed packages.
3. Do not replace a working backend just to standardize unless the task asks for
   packaging modernization.
4. If the import module differs from the normalized project name, configure
   `module-name` explicitly.

## pyproject.toml

```toml
[project]
name = "my-package"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = []

[build-system]
requires = ["uv_build>=0.9.28,<0.10.0"]
build-backend = "uv_build"
```

## Project Structure

Default layout uses `src/<normalized_project_name>/__init__.py`:

```
pyproject.toml
src/
└── my_package/
    └── __init__.py
```

Package name is normalized: `Foo-Bar` → `foo_bar`.

If the actual import package is not the normalized project name, configure it:

### Custom Module Location

```toml
[tool.uv.build-backend]
module-name = "mymodule"
module-root = ""  # Use project root instead of src/
```

### Namespace Packages

For `foo.bar` namespace:

```
src/foo/bar/__init__.py  # No __init__.py in foo/
```

```toml
[tool.uv.build-backend]
module-name = "foo.bar"
```

## File Inclusion/Exclusion

Excludes `__pycache__`, `*.pyc`, `*.pyo` by default.

```toml
[tool.uv.build-backend]
source-include = ["assets/**"]
source-exclude = ["/dist", "tests/**"]
```

- Includes are anchored (`pyproject.toml` = only root)
- Excludes are not anchored (`__pycache__` = all dirs named that)
- Use `/prefix` to anchor excludes

## Build Commands

```bash
uv build
uv lock --check
```

If a repository explicitly requires the PyPA `build` package:

```bash
uv run --with build python -m build
```

Do not run `uv run python -m build` and assume `build` is available; uv creates
an isolated environment and will not see a system-level `build` installation.

## Common Packaging Failure

| Symptom | Cause | Fix |
|---|---|---|
| Wheel contains `solidworks_compare` but code imports `solidworks_drawing_compare` | `uv_build` normalized the project name | Set `[tool.uv.build-backend].module-name = "solidworks_drawing_compare"` or keep the repo's existing backend. |
| Build passes locally but import fails in tests | Source layout and package discovery disagree | Verify `src/<module>/__init__.py` and `module-name`. |
| Extension package fails under `uv_build` | `uv_build` is for pure Python | Use the repo's extension-capable backend. |
