---
name: expo-firebase-stack
description: Diagnose and avoid the recurring traps in Expo + react-native-web + Firebase JS SDK apps — Google sign-in failing only inside chat-app browsers, DEVELOPER_ERROR on Android, emulator data that "does not exist", stale Metro bundles, unthemeable react-native-web controls, and live-query races that make seeds and tests silently do nothing. Use when building, debugging, or deploying an Expo app that shares one codebase across Android and web via react-native-web with Firebase for auth/Firestore/Functions.
---

# Expo + react-native-web + Firebase: the traps

Each entry is **symptom → cause → fix**, because the symptom is what you have
when you need this. In every case the symptom points somewhere other than the
cause — that is why they cost time.

**Rule that prevents most of the pain: verify by looking.** Take the screenshot
and read it; query the database rather than the UI. "The code looks right" has
been wrong often enough here that it is not evidence.

## Sign-in

### Works in a browser, fails from a WhatsApp/Slack link
`auth/missing-initial-state`, or a silent bounce back to sign-in.

Chat apps open an in-app webview with **partitioned storage**. The default
`authDomain` (`<project>.firebaseapp.com`) puts the auth helper on a *different
origin*, and the cross-origin handoff loses its state.

Two halves, **both** required:

1. GCP Console → APIs & Services → Credentials → the Firebase-created **Web
   client**:
   - Authorized JavaScript origins: `https://<project>.web.app`
   - Authorized redirect URIs: `https://<project>.web.app/__/auth/handler`
2. Code: `authDomain: '<project>.web.app'` — the *hosting* domain. Hosting serves
   `/__/auth/*` itself, keeping the redirect same-origin.

Register the redirect URI **before** flipping `authDomain`, or sign-in breaks for
everyone in between.

### Popups blocked in webviews
Fall back to redirect, and surface the failure:

```ts
getRedirectResult(auth).catch((e) => report(e, { source: 'redirectSignIn' }));

try {
  await signInWithPopup(auth, provider);
} catch (e) {
  const code = (e as { code?: string }).code;
  if (code === 'auth/popup-blocked' ||
      code === 'auth/operation-not-supported-in-this-environment') {
    await signInWithRedirect(auth, provider);
    return;
  }
  throw e;
}
```

`getRedirectResult` is not optional: a failed redirect surfaces **only** there.
Without it the user lands back on sign-in with no error recorded anywhere.

### Android: `DEVELOPER_ERROR`
Works on web, opaque failure on Android — looks like a code bug, is not.

`google-services.json` has no `client_type: 1` (Android OAuth client). Adding the
SHA-1 in the console does **not** update a file you already downloaded.

Add the SHA-1, **re-download** the file, then verify before building:

```sh
python3 -c "import json;d=json.load(open('app/google-services.json'));print([o['client_type'] for o in d['client'][0]['oauth_client']])"
```

`1` must be present. Pass the **web** client id (`client_type: 3`) as
`webClientId` — passing the Android id is its own `DEVELOPER_ERROR`.

Debug SHA-1 (RN's debug keystore is committed, so this is stable per repo):

```sh
keytool -list -v -keystore app/android/app/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android
```

The **release** key differs and must be registered separately before shipping.

### "Make internal" greyed out on the OAuth consent screen
Internal requires the Cloud project to belong to a **Google Cloud organization**.
A project created under a personal account has none.

Either move the project into the Workspace org (keeps project id and data), or
accept External — and then **publish it**, because in `Testing` only
explicitly-listed test users can sign in at all.

Either way, enforce any domain restriction **server-side**. The client `hd`
parameter is UX; it is trivially bypassed.

### Reject by deleting, not by marking
An auth-create trigger that rejects an out-of-domain account should `deleteUser`
it. Writing `status: 'rejected'` leaves junk that is indistinguishable from real
pending users.

## Firebase emulators

### Writes succeed, triggers log success, client says the doc does not exist
The listener even reports a *server* snapshot (`fromCache=false`).

The Firestore emulator **partitions data by project id**. A client configured
with a different id talks to a different database inside the same emulator.

Use one exported constant for the emulator project id on both client and server,
and pass the same value to `firebase emulators:exec --project`.

### One snapshot, then silence (React Native only)
The WebChannel stream dies silently under RN networking. Use
`experimentalForceLongPolling` on native, `experimentalAutoDetectLongPolling` on
web.

### Secret Manager 403 for every bound secret
`secrets: [...]` makes the emulator reach for real Secret Manager. Override in
`functions/.secret.local` (gitignored). An **empty value is not treated as an
override**, so the 403 may persist — document it, or people learn to ignore
emulator errors.

### Cloud Build: `404 <pkg> is not in this registry` for your own workspace package
Functions deploy uploads only the functions directory, so a private workspace
package cannot be resolved up there. Bundle it (esbuild `bundle: true`) **and
remove it from `functions/package.json` entirely.**

`devDependencies` is *not* sufficient — the Cloud Functions Node buildpack
installs those too. The declaration has to be gone.

It still resolves locally: npm workspaces symlinks every workspace package into
the root `node_modules` regardless of who declares it, so the bundler finds it
at build time with no declaration at all.

Verify the bundle is self-contained instead of assuming:

```sh
grep -c 'require("<pkg>")' functions/lib/index.js   # must be 0
```

### Rules pass locally, queries fail in production
The emulator does **not** enforce composite indexes. Probe every composite index
against production before launch.

## Expo / Metro / builds

### A UI change appears to have no effect
Screenshots come back byte-identical across a real code change.

A long-running `expo start` went stale and serves a bundle that no longer matches
source. **Restart the dev server before concluding the code is wrong.** Compare
screenshot file sizes — byte-identical output across a real change means a stale
bundle, not an ineffective fix.

### A successful build red-screens quoting another repo's paths
Metro's port 8081 is machine-wide, and an Android emulator reaches it at
`10.0.2.2:8081` — the host directly — so `adb reverse` does not redirect it.
Whoever holds 8081 serves your app. Add a preflight that refuses to start when
8081 belongs to another project.

### Works in dev, gone in the exported build
`expo export` sets `__DEV__` to **false**, so anything gated on it is stripped —
correctly, but surprisingly. E2E flows needing dev-only affordances must drive
`expo start`, not the export; assert the *absence* separately so the safety
property is tested rather than assumed.

### Stale config baked into a bundle
`EXPO_PUBLIC_*` is **inlined at build time**. Build with `--clear` when config
changes. Corollary: `EXPO_PUBLIC_*` can never hold a secret — anyone with the app
has it.

## react-native-web

### A control ignores your theme colours
`Switch` ignores `thumbColor`/`trackColor`, and the RNW-specific
`activeThumbColor`/`activeTrackColor` are gone in 0.21 — it renders Material
teal. Build toggles from `Pressable` and views you control. Assume any RNW
control wrapping a platform widget may not be themeable, and confirm with a
screenshot rather than trusting the props.

### There is no dropdown primitive in React Native
Use a platform seam: `<select>` on web (keyboard nav, type-ahead and scrolling
for free), a height-bounded modal list on native. Rendering one button per option
is the trap — fine with three options, fills the screen with twelve.

### Emoji arrows ignore text colour
`◀`/`▶` render as colour glyphs. Use text-presentation characters (`‹`, `›`, `▾`)
or draw them.

### Branch layout on WIDTH, not platform
A tablet deserves the desktop layout; a narrow window deserves the phone one.
Treat drag-and-drop as a *capability* layered on the wide layout, not a platform
feature.

## Observability

### Test runs pollute the production error project
Gate reporting on the same flag that points the app at emulators. Beyond wasting
quota, the browser SDK wraps `fetch` for breadcrumbs and beacons to an ingest
host a sandbox cannot reach — enough to stall a sign-in flow and fail a suite.

### Do not run `@sentry/wizard` on a repo with committed native directories
It rewrites native files and metro config and writes a `sentry.properties`
containing a real auth token. Wire the SDK by hand.

### Serverless events never arrive
The instance can freeze the moment the handler resolves. `await Sentry.flush(...)`
before returning. Exclude expected domain errors (`HttpsError`) or real defects
drown in users mistyping things.

### Send the uid, not the email
It correlates with your users collection — all triage needs — without putting
user addresses into a third-party service.

## Testing and seeding

### A seed or test silently did nothing, repeatedly
Duplicate records, or an approval loop that approved nobody.

**A live query returns empty before it returns data, and empty is
indistinguishable from absent.** Sampling the UI immediately after navigating
gets the empty state, so an "already exists?" guard says no and creates another.

Wait for the list to *render* before deciding something is absent, and verify
against the database directly rather than the UI.

### Confirmation dialogs silently do nothing under Playwright
Playwright **auto-dismisses** `window.confirm`. Register the handler, and assert
on the text so the test proves a confirmation was demanded:

```js
page.on('dialog', async (d) => { lastConfirm.set(page, d.message()); await d.accept(); });
```

## Worked example: "sign-in is broken on phones"

A tester reports the deployed web app fails to sign in from a link someone sent
in WhatsApp. It works on their laptop.

1. **Reproduce in the right context.** A desktop browser will not show it. The
   distinguishing factor is an in-app webview with partitioned storage.
2. **Read the actual error.** `auth/missing-initial-state` — state lost between
   origins, not a credentials problem. If instead sign-in does nothing at all,
   suspect a blocked popup.
3. **Fix the origin split.** Register `https://<project>.web.app` and
   `https://<project>.web.app/__/auth/handler` on the Web OAuth client, *then*
   set `authDomain` to the hosting domain and redeploy.
4. **Fix the popup path too.** Add the redirect fallback and `getRedirectResult`
   — they are separate failures with the same report ("sign-in doesn't work").
5. **Verify in a webview**, not a desktop browser, and confirm a failed redirect
   now produces an error you can see.

Two independent causes hide behind one user-visible symptom. Fixing only the one
you reproduced leaves a bug that resurfaces as "it still doesn't work sometimes".
