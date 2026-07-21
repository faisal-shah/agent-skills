# expo-firebase-stack

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
for diagnosing the recurring traps in **Expo + react-native-web + Firebase JS
SDK** apps — one codebase serving Android and web, with Firebase for auth,
Firestore and Cloud Functions.

> **Part of [agent-skills](../../README.md).**

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| SKILL.md   | yes | Symptom → cause → fix entries, plus a worked diagnosis |
| README.md  | no  | Human-facing usage notes (this file) |
| AGENTS.md  | no  | AI context for developing this skill |
| install.sh | yes | Installs the skill (bash) |
| install.ps1| yes | Installs the skill (PowerShell) |

## What it covers

Bugs whose **symptom points away from the cause**, which is why they cost an
afternoon each the first time:

- **Sign-in** — works in a browser, fails from a WhatsApp/Slack link
  (`missing-initial-state`); popups blocked in webviews; `DEVELOPER_ERROR` on
  Android; "Make internal" greyed out on the consent screen.
- **Emulators** — writes that succeed while the client insists the document does
  not exist; one snapshot then silence on React Native; Secret Manager 403s;
  composite indexes that are only enforced in production.
- **Expo / Metro** — a UI change that appears to do nothing because the dev
  server went stale; a clean build red-screening with another repo's module
  paths; `__DEV__` flipping to false in an export.
- **react-native-web** — controls that ignore your theme, the missing dropdown
  primitive, emoji glyphs that ignore text colour, layout that must branch on
  width rather than platform.
- **Observability** — test runs polluting the production error project;
  serverless events that never arrive; why not to run `@sentry/wizard` on a repo
  with committed native directories.
- **Testing and seeding** — live queries returning empty before returning data,
  which makes idempotent seeds create duplicates and approval loops approve
  nobody; Playwright auto-dismissing `window.confirm`.

## Installation

**Linux / macOS / WSL:**

```bash
./skills/expo-firebase-stack/install.sh                          # both Copilot and Codex
./skills/expo-firebase-stack/install.sh --copilot                # Copilot only
./skills/expo-firebase-stack/install.sh --claude                 # Claude Code only
./skills/expo-firebase-stack/install.sh --skills-dir .github/skills
./skills/expo-firebase-stack/install.sh --uninstall
```

**Windows (PowerShell):**

```powershell
.\skills\expo-firebase-stack\install.ps1
.\skills\expo-firebase-stack\install.ps1 -Copilot
.\skills\expo-firebase-stack\install.ps1 -Claude
.\skills\expo-firebase-stack\install.ps1 -SkillsDir .github\skills
.\skills\expo-firebase-stack\install.ps1 -Uninstall
```

## Prerequisites

None to read. To act on it: an Expo project, the Firebase CLI, and Android SDK
tooling (`keytool`) for the signing-certificate entries.

## Scope

Deliberately **stack-level, not app-level** — no project ids, domains, or
business rules, since this repo is public. Entries are only added after a bug has
actually cost time; speculative advice is left out so the rest stays
trustworthy. See [AGENTS.md](AGENTS.md) before editing.
