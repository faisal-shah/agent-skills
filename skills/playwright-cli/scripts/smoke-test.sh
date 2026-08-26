#!/usr/bin/env bash
set -euo pipefail
export NO_UPDATE_NOTIFIER=1

browser="${1:-chromium}"
session_name="skill-smoke-$$"
temp_directory="$(mktemp -d)"

cleanup() {
    (
        cd "$temp_directory"
        playwright-cli -s="$session_name" close >/dev/null 2>&1 || true
    )
    rm -rf -- "$temp_directory"
}
trap cleanup EXIT INT TERM

cd "$temp_directory"
playwright-cli -s="$session_name" open about:blank --browser="$browser"
playwright-cli -s="$session_name" run-code \
    "async page => { await page.setContent('<!doctype html><title>playwright-cli smoke test</title><h1>ready</h1>'); }"

title_matches="$(playwright-cli --raw -s="$session_name" eval "document.title === 'playwright-cli smoke test'")"
if [[ "$title_matches" != "true" ]]; then
    echo "Unexpected title comparison: $title_matches" >&2
    exit 1
fi

playwright-cli -s="$session_name" screenshot --filename="$temp_directory/smoke.png"
test -s "$temp_directory/smoke.png"
playwright-cli -s="$session_name" close

trap - EXIT INT TERM
rm -rf -- "$temp_directory"
echo "playwright-cli browser lifecycle smoke test passed with $browser."
