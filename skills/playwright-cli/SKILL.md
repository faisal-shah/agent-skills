---
name: playwright-cli
description: Automates browser interactions for web testing, form filling, screenshots, and data extraction. Use when the user needs to navigate websites, interact with web pages, fill forms, take screenshots, test web applications, or extract information from web pages.
allowed-tools: Bash(playwright-cli:*)
---

# Browser Automation with playwright-cli

## Quick start

```bash
# open new browser
playwright-cli open
# navigate to a page
playwright-cli goto https://playwright.dev
# interact with the page using refs from the snapshot
playwright-cli click e15
playwright-cli type "page.click"
playwright-cli press Enter
# take a screenshot
playwright-cli screenshot
# close the browser
playwright-cli close
```

## Commands

### Core

```bash
playwright-cli open
# open and navigate right away
playwright-cli open https://example.com/
playwright-cli goto https://playwright.dev
playwright-cli type "search query"
playwright-cli click e3
playwright-cli dblclick e7
playwright-cli fill e5 "user@example.com"
playwright-cli drag e2 e8
playwright-cli hover e4
playwright-cli select e9 "option-value"
playwright-cli upload ./document.pdf
playwright-cli check e12
playwright-cli uncheck e12
playwright-cli snapshot
playwright-cli snapshot --filename=after-click.yaml
playwright-cli eval "document.title"
playwright-cli eval "el => el.textContent" e5
playwright-cli dialog-accept
playwright-cli dialog-accept "confirmation text"
playwright-cli dialog-dismiss
playwright-cli resize 1920 1080
playwright-cli close
```

### Navigation

```bash
playwright-cli go-back
playwright-cli go-forward
playwright-cli reload
```

### Keyboard

```bash
playwright-cli press Enter
playwright-cli press ArrowDown
playwright-cli keydown Shift
playwright-cli keyup Shift
```

### Mouse

```bash
playwright-cli mousemove 150 300
playwright-cli mousedown
playwright-cli mousedown right
playwright-cli mouseup
playwright-cli mouseup right
playwright-cli mousewheel 0 100
```

### Save as

```bash
playwright-cli screenshot
playwright-cli screenshot e5
playwright-cli screenshot --filename=page.png
playwright-cli pdf --filename=page.pdf
```

### Tabs

```bash
playwright-cli tab-list
playwright-cli tab-new
playwright-cli tab-new https://example.com/page
playwright-cli tab-close
playwright-cli tab-close 2
playwright-cli tab-select 0
```

### Storage

```bash
playwright-cli state-save
playwright-cli state-save auth.json
playwright-cli state-load auth.json

# Cookies
playwright-cli cookie-list
playwright-cli cookie-list --domain=example.com
playwright-cli cookie-get session_id
playwright-cli cookie-set session_id abc123
playwright-cli cookie-set session_id abc123 --domain=example.com --httpOnly --secure
playwright-cli cookie-delete session_id
playwright-cli cookie-clear

# LocalStorage
playwright-cli localstorage-list
playwright-cli localstorage-get theme
playwright-cli localstorage-set theme dark
playwright-cli localstorage-delete theme
playwright-cli localstorage-clear

# SessionStorage
playwright-cli sessionstorage-list
playwright-cli sessionstorage-get step
playwright-cli sessionstorage-set step 3
playwright-cli sessionstorage-delete step
playwright-cli sessionstorage-clear
```

### Network

```bash
playwright-cli route "**/*.jpg" --status=404
playwright-cli route "https://api.example.com/**" --body='{"mock": true}'
playwright-cli route-list
playwright-cli unroute "**/*.jpg"
playwright-cli unroute
```

### DevTools

```bash
playwright-cli console
playwright-cli console warning
playwright-cli network
playwright-cli run-code "async page => await page.context().grantPermissions(['geolocation'])"
playwright-cli tracing-start
playwright-cli tracing-stop
playwright-cli video-start
playwright-cli video-stop video.webm
```

### Install

```bash
# Install a browser (first-time setup only — skip if a browser is already available).
# Uses the bundled Chromium by default. If it fails looking for "chrome",
# set the browser explicitly:
PLAYWRIGHT_MCP_BROWSER=chromium playwright-cli install-browser

# To install a specific browser:
playwright-cli install-browser --browser=firefox

# NOTE: Do NOT run "playwright-cli install --skills" — this skill is already
# installed by virtue of being in ~/.copilot/skills/.
```

### Configuration
```bash
# If no config file exists and "chrome" is not installed, set the browser
# via environment variable so open works from any directory:
export PLAYWRIGHT_MCP_BROWSER=chromium

# Use specific browser when creating session
playwright-cli open --browser=chrome
playwright-cli open --browser=firefox
playwright-cli open --browser=webkit
playwright-cli open --browser=msedge
# Connect to browser via extension
playwright-cli open --extension

# Use persistent profile (by default profile is in-memory)
playwright-cli open --persistent
# Use persistent profile with custom directory
playwright-cli open --profile=/path/to/profile

# Start with config file
playwright-cli open --config=my-config.json

# Close the browser
playwright-cli close
# Delete user data for the default session
playwright-cli delete-data
```

### Browser Sessions

```bash
# create new browser session named "mysession" with persistent profile
playwright-cli -s=mysession open example.com --persistent
# same with manually specified profile directory (use when requested explicitly)
playwright-cli -s=mysession open example.com --profile=/path/to/profile
playwright-cli -s=mysession click e6
playwright-cli -s=mysession close  # stop a named browser
playwright-cli -s=mysession delete-data  # delete user data for persistent session

playwright-cli list
# Close all browsers
playwright-cli close-all
# Forcefully kill all browser processes
playwright-cli kill-all
```

## Working with local files (file:// URLs)

By default, `file://` navigation is **blocked**. To open local HTML files or
other local content, you must enable unrestricted file access using **one** of
these methods:

### Method 1: Inline environment variables (recommended for quick use)

```bash
# Inline vars — no shell pollution, no cleanup needed
PLAYWRIGHT_MCP_BROWSER=chromium PLAYWRIGHT_MCP_ALLOW_UNRESTRICTED_FILE_ACCESS=true \
  playwright-cli open file:///path/to/page.html
```

### Method 2: Config file (recommended for repeated use)

Create `playwright-cli.json` in your working directory:

```json
{
  "allowUnrestrictedFileAccess": true
}
```

Then simply:

```bash
playwright-cli open file:///path/to/page.html
```

Or pass the config explicitly:

```bash
playwright-cli open --config=playwright-cli.json file:///path/to/page.html
```

### Example: Inspect a local HTML file

```bash
PLAYWRIGHT_MCP_BROWSER=chromium PLAYWRIGHT_MCP_ALLOW_UNRESTRICTED_FILE_ACCESS=true \
  playwright-cli open file:///home/user/project/index.html
playwright-cli snapshot
playwright-cli screenshot --filename=local-page.png
playwright-cli close
```

### Example: Test a local build output

```bash
PLAYWRIGHT_MCP_BROWSER=chromium PLAYWRIGHT_MCP_ALLOW_UNRESTRICTED_FILE_ACCESS=true \
  playwright-cli open file:///home/user/project/dist/index.html
playwright-cli snapshot
playwright-cli click e3
playwright-cli snapshot
playwright-cli close
```

### Notes on file:// paths

- Paths must be **absolute** and use the `file:///` prefix (three slashes)
- On WSL, Windows paths are accessible via `/mnt/<drive>/...`,
  e.g. `file:///mnt/d/projects/site/index.html`
- The env var / config applies to the session — set it on the `open` command (inline) or before it

## Example: Form submission

```bash
playwright-cli open https://example.com/form
playwright-cli snapshot

playwright-cli fill e1 "user@example.com"
playwright-cli fill e2 "password123"
playwright-cli click e3
playwright-cli snapshot
playwright-cli close
```

## Example: Multi-tab workflow

```bash
playwright-cli open https://example.com
playwright-cli tab-new https://example.com/other
playwright-cli tab-list
playwright-cli tab-select 0
playwright-cli snapshot
playwright-cli close
```

## Example: Debugging with DevTools

```bash
playwright-cli open https://example.com
playwright-cli click e4
playwright-cli fill e7 "test"
playwright-cli console
playwright-cli network
playwright-cli close
```

```bash
playwright-cli open https://example.com
playwright-cli tracing-start
playwright-cli click e4
playwright-cli fill e7 "test"
playwright-cli tracing-stop
playwright-cli close
```

## Tips & patterns

### Repeat keypresses (slide decks, pagination)

`press` has no `--repeat` flag. Use a bash loop to press a key N times:

```bash
for i in $(seq 1 11); do playwright-cli press ArrowRight 2>&1 | tail -1; done
```

For JS-driven slide decks (Reveal.js, Impress, etc.), prefer `eval` to jump directly:

```bash
playwright-cli eval "Reveal.slide(11)"          # Reveal.js
playwright-cli eval "impress().goto('step-11')" # Impress.js
```

### High-resolution screenshots for detail verification

Resize the viewport before capturing to get 4K screenshots — essential for
verifying small text, SVG glyphs, or chart labels:

```bash
playwright-cli resize 3840 2160
playwright-cli screenshot --filename=detail-4k.png
```

### Edit → Reload → Verify workflow

When iterating on a local file, use `reload` instead of close/reopen to keep
your navigation state (scroll position, current slide, expanded sections):

```bash
# ... edit the file ...
playwright-cli reload
playwright-cli screenshot --filename=after-fix.png
```

## Specific tasks

* **Request mocking** [references/request-mocking.md](references/request-mocking.md)
* **Running Playwright code** [references/running-code.md](references/running-code.md)
* **Browser session management** [references/session-management.md](references/session-management.md)
* **Storage state (cookies, localStorage)** [references/storage-state.md](references/storage-state.md)
* **Test generation** [references/test-generation.md](references/test-generation.md)
* **Tracing** [references/tracing.md](references/tracing.md)
* **Video recording** [references/video-recording.md](references/video-recording.md)
