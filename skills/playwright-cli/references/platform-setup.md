# Platform Setup

Use the CLI installed in the same operating environment as the browser. Do not
mix a Windows Node/npm installation with a WSL shell or invoke Windows npm
shims through `/mnt/c`.

## Windows PowerShell

```powershell
npm install --global @playwright/cli@latest
$env:NO_UPDATE_NOTIFIER = '1'
playwright-cli --version
playwright-cli install-browser chromium
```

The skill installer applies a guarded compatibility repair to the global CLI.
It suppresses a Node.js 24 update-notifier crash and prevents the detached
daemon, browser, and `taskkill.exe` cleanup from opening Windows Terminal tabs.
Re-run the installer after every global CLI upgrade:

```powershell
# Install the skill and apply the repair automatically.
& "$HOME\path\to\agent-skills\skills\playwright-cli\install.ps1" -Codex

# Or repair/check an existing global CLI directly from the skill source.
& "$HOME\path\to\agent-skills\skills\playwright-cli\scripts\repair-windows-playwright-cli.ps1"
& "$HOME\path\to\agent-skills\skills\playwright-cli\scripts\repair-windows-playwright-cli.ps1" -Check
```

The repair is idempotent and fails closed if an upstream release changes the
expected code structure. It does nothing on non-Windows systems. The notifier
workaround is limited to Windows on Node.js 24 or newer and can be removed once
the upstream [Node.js issue](https://github.com/nodejs/node/issues/56645) and
[Playwright report](https://github.com/microsoft/playwright/issues/42402) are
resolved.

For pages using Windows Integrated Authentication, use the Windows CLI with
Edge unless the environment has explicitly configured another browser:

```powershell
playwright-cli -s=corp-read open 'https://intranet.example/path?a=1&b=2' --browser=msedge --persistent
```

Use a dedicated automation profile. Do not point `--profile` at a profile that
is simultaneously open in an interactive browser.

## Linux

Install Node.js and npm through the distribution or a version manager, then:

```bash
npm install --global @playwright/cli@latest
export NO_UPDATE_NOTIFIER=1
playwright-cli --version
playwright-cli install-browser chromium
```

Headless mode is the default and does not require a desktop session. Use
`--headed` only when a display server is available and visual interaction is
needed.

Use Node.js 20 or newer. If a corporate TLS proxy causes
`SELF_SIGNED_CERT_IN_CHAIN` while installing the browser, provide the trusted
corporate CA instead of disabling certificate verification:

```bash
export NODE_EXTRA_CA_CERTS="$HOME/.config/corporate-ca.pem"
playwright-cli install-browser chromium
```

## WSL

Install Node.js, npm, `playwright-cli`, and its browser inside WSL exactly as on
Linux. Headless Chromium is the most reliable default:

```bash
npm install --global @playwright/cli@latest
export NO_UPDATE_NOTIFIER=1
playwright-cli install-browser chromium
playwright-cli -s=wsl-check open https://example.com --browser=chromium
```

Before using the CLI, verify that WSL is not resolving a Windows npm shim:

```bash
type -a node npm playwright-cli
./scripts/doctor.sh
```

If `playwright-cli` resolves below `/mnt/c`, install it natively in WSL and put
the native npm bin directory before imported Windows paths. Do not paper over
an obsolete system Node.js with the Windows executable; upgrade the WSL Node.js
runtime to a supported release instead.

WSL browser processes do not automatically inherit Windows browser profiles or
Windows Integrated Authentication. For an intranet that depends on Windows
SSO, run the Windows CLI from PowerShell instead. Attach through CDP only when
the user explicitly chooses that setup, and never expose a debugging endpoint
beyond the local machine.

Windows files are under `/mnt/<drive>` in WSL. Convert paths before using file
URLs:

```bash
playwright-cli open 'file:///mnt/c/work/site/index.html'
```

## Environment variables

```bash
export PLAYWRIGHT_CLI_SESSION=docs-check
export PLAYWRIGHT_MCP_BROWSER=chromium
export NO_UPDATE_NOTIFIER=1
```

```powershell
$env:PLAYWRIGHT_CLI_SESSION = 'docs-check'
$env:PLAYWRIGHT_MCP_BROWSER = 'msedge'
$env:NO_UPDATE_NOTIFIER = '1'
```

Prefer a checked-in `.playwright/cli.config.json` for repeatable project
settings. Use environment variables for temporary machine-specific overrides.

## Lifecycle smoke test

The bundled smoke tests use a unique session and a harmless local page. A
successful test opens the session, evaluates the title, captures a screenshot,
closes the session, and removes its temporary artifacts.

Run `doctor.ps1` or `doctor.sh` first. The doctor fails on unsupported Node.js,
a missing CLI, or a Windows CLI leaking into WSL, and warns when TLS validation
has been disabled.

```bash
./scripts/smoke-test.sh
```

```powershell
.\scripts\smoke-test.ps1
```

The equivalent manual sequence is:

```bash
session="smoke-$$"
trap 'playwright-cli -s="$session" close >/dev/null 2>&1 || true' EXIT
playwright-cli -s="$session" open about:blank --browser=chromium
playwright-cli -s="$session" eval "document.title"
playwright-cli -s="$session" close
playwright-cli list
```

```powershell
$session = "smoke-$PID"
try {
    playwright-cli "-s=$session" open about:blank --browser=msedge
    playwright-cli "-s=$session" eval "document.title"
} finally {
    playwright-cli "-s=$session" close
}
playwright-cli list
```

## Troubleshooting

| Symptom | Response |
|---|---|
| `playwright-cli` is missing | Install `@playwright/cli@latest` in the current OS environment. |
| WSL resolves `/mnt/c/.../playwright-cli` | Install Node.js and the CLI natively in WSL, then put the native npm bin directory before Windows paths. |
| Browser executable is missing | Run `playwright-cli install-browser chromium`, or choose an installed channel. |
| A Windows Terminal tab exits with code 128 | Re-run the Windows repair after the latest npm upgrade, then perform one smoke test. |
| Node.js 24 exits with a `UV_HANDLE_CLOSING` assertion | Set `NO_UPDATE_NOTIFIER=1` for the current shell and rerun the Windows repair. This is the upstream Node.js update-notifier bug, not a browser or site failure. |
| A session disappears between commands | Check `playwright-cli list`; avoid mixing Windows and WSL clients or changing working roots mid-session. |
| An intranet page shows a login page in WSL | Use Windows Edge automation for Windows SSO. |
| A previously working site suddenly times out | Retry one read, then check VPN, DNS, proxy, and server health before changing automation code. |
| npm warns that TLS verification is disabled | Remove `NODE_TLS_REJECT_UNAUTHORIZED=0` and configure the corporate CA instead of suppressing certificate validation. |
| Browser download reports `SELF_SIGNED_CERT_IN_CHAIN` | Set `NODE_EXTRA_CA_CERTS` to the trusted corporate CA bundle, then retry. Do not disable TLS verification. |
| Node or browser installation reports `ENOSPC` | Free space in that Linux/WSL filesystem; browser bundles need substantial headroom. |
