# User Preferences

## Execution Style

- **Work autonomously:** When given full permissions or a well-defined task, continue without stopping for updates. Only pause when genuinely blocked (missing dependency, ambiguous requirement, etc.).
- **Defensive programming at boundaries only:** Validate external inputs and library boundaries. Internally within a module/library, assume strict contracts and well-defined interfaces. Do not add unnecessary fallback code, backwards compatibility layers, or defensive "just in case" logic for internal calls.
- **Greenfield mindset:** This is production code under active development with no legacy constraints. Prefer clean refactors over patches. Bold architectural changes are welcome if they improve correctness, simplicity, or performance.

## Testing & Verification

- **Always test before reporting completion:**
  - Run existing test suites after changes (mandatory)
  - Smoke test GUIs by loading real data and exercising features
  - Test on real datasets or sample logs when available
  - For Cython/Python hybrid codebases, verify parity between implementations
- **shellcheck deliverable shell scripts:** Run `shellcheck` on every `.sh` file created or edited as a project artifact (committed scripts, templates, generated outputs). Fix all warnings. Do NOT lint ephemeral one-liners or inline bash used during task execution.
- **Profile before optimizing:** Use real data to identify bottlenecks. When performance is critical, target dramatic speedups (10-100x).

## Tool Preferences

- **Python:** Always use `python3` (never just `python`)
- **JSON:** Use `orjson` (not stdlib json) for performance-critical code
- **GUI:** Use `PyQt5` (not PyQt6, PySide6, or tkinter)
- **Performance:** Consider `Cython` for hot paths when significant speedups (10-100x) are needed
- **Testing:** Use `pytest-qt` for GUI testing and screenshots
- **CLI tools:** Use `ripgrep` (rg) for searches, `jq` for JSONL processing
- **Long-running processes:** Use `tmux` (keep sessions alive, don't kill/recreate)
- **Diagrams:** Use mermaid extensively in documentation
- **Scripts:** Write one-off Python scripts with [PEP 723](https://peps.python.org/pep-0723/) inline metadata front matter (e.g. `# /// script` block with dependencies) so they can be run with `uv run`

## Documentation & Commits

- **Update docs alongside code:** CHANGELOG.rst, schema docs (*.rst), README/guides
- **Git commits:** 50 char subject (imperative mood), 70 char wrapped body, senior engineer audience
- **AGENTS.md:** Check repo roots for AI-specific context; create when appropriate for session handoff
- **Use mermaid diagrams** for architecture, protocols, and state machines

## File Management

- Use the system temp directory (`/tmp` on Linux/macOS, `$env:TEMP` on Windows) for any temporary files, cloned repos, or scratch work. Never place them in the home directory or working directory.
- **Git worktrees:** When you need to checkout a different branch without switching the current branch, use `git worktree add /tmp/<worktree-name> <branch>` instead of cloning or switching branches.

## Python Package Inspection

- **Find installed package source:** `python3 -c "import <pkg>; print(<pkg>.__file__)"` gives the `__init__.py` path; the parent directory is the package root. Use `python3 -m pip show <pkg>` for metadata (version, location, dependencies).
- Use this when you need to read the source of an installed dependency to understand its API, debug behavior, or find bundled resources (docs, skills, data files).

## Research & Analysis

- Use web searches to understand topics in greater detail when the additional background would produce a better result.
- When analyzing documents (PDFs, DOCX, etc.), be thorough: extract all text, analyze images/drawings, and provide comprehensive coverage.

## Context7 (Library Documentation)

- **Use Context7** when writing code against external libraries/frameworks, when unsure about API signatures or parameters, or when a library may have recent breaking changes. Call `resolve_library_id` first, then `get_library_docs` for the specific topic.
- **Don't use Context7** for general programming concepts, language-level questions, or project-internal code already visible in the repo.
- **Prefer Context7 over web search** for library docs (structured, token-efficient). Fall back to web search only if Context7 doesn't cover the library.
