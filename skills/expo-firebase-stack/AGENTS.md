# AGENTS.md — expo-firebase-stack

## What this skill is

A field guide to the recurring failure modes of **Expo + react-native-web +
Firebase JS SDK** apps: one codebase serving Android and web, with Firebase for
auth, Firestore and Cloud Functions.

It is not a tutorial. It assumes the agent can already build the app, and exists
for the moments when something fails in a way that points at the wrong cause.

## Why it exists

These bugs share a shape: **the symptom is remote from the cause.** Sign-in
failing only from a chat app looks like an auth bug and is an origin/storage
problem. `DEVELOPER_ERROR` on Android looks like code and is a stale JSON file. A
missing document looks like a rules failure and is a project-id namespace. Each
one costs an afternoon the first time and five minutes once written down.

## Editing rules

1. **Symptom first.** Entries are ordered and worded so they can be found by the
   thing you are staring at, not by the subsystem they belong to. Keep the
   symptom as the heading or the first line.

2. **Only entries that were actually paid for.** This is a record of bugs that
   cost real time, not a list of everything that could go wrong. Speculative
   advice dilutes it and makes the rest less trustworthy.

3. **Keep it stack-level, never app-specific.** No project ids, client ids,
   fingerprints, domains, or business rules. **The repo is public.** Anything
   pasted from a real project must be generalised to `<project>` placeholders
   before it lands here.

4. **SKILL.md is the artifact and is loaded in full on every invocation.** Every
   line costs context. Prefer deleting a marginal entry over adding a caveat to
   it. State the fix; do not narrate the investigation.

5. **Keep the worked example.** It carries the diagnostic *method* — reproduce in
   the right context, read the actual error, expect more than one cause behind
   one report — which generalises past the specific entries.

## Adding an entry

Use the existing shape:

```markdown
### <what you observed>
<one or two lines: what is actually happening>

<the fix, concretely — a command, a config line, a code block>
```

If a fix has an ordering constraint (register the redirect URI *before* flipping
`authDomain`), say so explicitly. Those are the steps people get wrong.

## Provenance

Distilled from two production Expo/Firebase apps. Contributions should come from
real diagnosis, with the generalisation done deliberately rather than by
find-and-replace.
