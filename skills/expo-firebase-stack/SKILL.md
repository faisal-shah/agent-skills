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

Read **"How this stack fools you"** at the end before debugging anything
subtle. Every entry below was found the slow way, and several were "fixed" wrongly
first — the failure modes here are unusually good at imitating success.

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

### No admin exists yet, and only an admin can promote anyone
The bootstrap deadlock after a first deploy. The usual answer — an Admin SDK
script — needs gcloud ADC or a service-account key, which a CI box or a fresh
laptop often does not have.

Ship a **temporary one-shot HTTP function: deploy, call once, delete.** Make it
safe by construction rather than by secrecy:

- it can only ever promote **one hardcoded address**, so whoever calls it the
  outcome is identical and there is nothing to gain by racing;
- it **refuses once any admin exists**, so it cannot be replayed after someone
  is demoted;
- it re-checks the domain/verified-email rule.

Those three together mean it needs no auth and no shared secret — and a secret
would be worse, since it would have to be transmitted somewhere.

```ts
const admins = await db.collection('users').where('role', '==', 'admin').get();
if (admins.docs.some((d) => d.data().status === 'active')) {
  res.status(409).json({ ok: false, reason: 'Admin exists; this is spent.' });
  return;
}
// set custom claims FIRST (rules trust the token), then the display mirror
```

Set **claims before the mirror document**: rules trust the token, so a failure
in between leaves a working admin rather than a document claiming access the
token does not grant. Delete the function immediately afterwards — and have it
say so in its own success response, so the cleanup step is hard to forget.

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
The emulator enforces **no indexes at all**, so a query that passes every local
test can fail the first time a real user runs it. Probe the real query shapes
against production with the **Admin SDK** — it bypasses rules but *not* index
requirements, so it tests exactly this without needing a signed-in user.

Two traps hide here:

**A bare collection-group `array-contains` needs a single-field index
EXEMPTION, not a composite index.** Array fields are not indexed at
collection-group scope by default. It goes in `fieldOverrides`, not `indexes`:

```json
{ "collectionGroup": "cards", "fieldPath": "assigneeUids",
  "indexes": [{ "arrayConfig": "CONTAINS", "queryScope": "COLLECTION_GROUP" }] }
```

**"Deployed" is not "ready."** `firebase firestore:indexes` lists definitions but
no build state, and an index still `CREATING` errors on use exactly like a
missing one — ~4 minutes even on an empty database. Read the true state:

```sh
curl -s -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  "https://firestore.googleapis.com/v1/projects/<project>/databases/(default)/collectionGroups/<coll>/fields/<field>"
```

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

### A screen renders on web but is BLANK on device
Header and buttons draw; the main content does not.

A View with **no flex** between a `flex: 1` container and a `flex: 1` child sizes
to its *content*, so the child collapses to zero height on native. Anything that
sizes to its own content (a header row) still draws, which makes it look like
one section is missing rather than the layout being broken.
react-native-web resolves the same tree differently, so web looks fine
throughout.

Suspect any conditional style that can evaluate to `undefined`:

```jsx
<View style={capped ? styles.capped : undefined}>   // collapses on native
<View style={[!scroll && styles.fill, capped ? styles.capped : null]}>  // fixed
```

**Never diagnose this from the web build.** The web/native divergence *is* the
bug.

### Android Back / edge-swipe exits the app instead of going back
A hand-rolled navigation stack is invisible to Android, so the OS sees an
activity with nothing to pop and leaves the app from any screen.

```ts
BackHandler.addEventListener('hardwareBackPress', () => {
  if (stack.length > 1) { pop(); return true; }  // consume
  return false;                                   // at root, let Android exit
});
```

Returning `false` at the root is deliberate — exiting from the first screen is
what people expect. `BackHandler` is a no-op shim on react-native-web, so it is
safe to call unconditionally. Browser Back is a *separate* problem: a custom
stack pushes no history entries.

### The keyboard covers the field you are typing into
Under **edge-to-edge** (`edgeToEdgeEnabled=true`, the default on newer Android)
two things stop working at once, and neither announces itself:

- `android:windowSoftInputMode="adjustResize"` no longer shrinks the window, so
  the keyboard **overlays** content;
- React Native's own `Keyboard` events **do not fire at all**.

That second one is the trap. The obvious fix — listen for `keyboardDidShow` and
add bottom padding — compiles, runs, throws nothing, and does **nothing**,
because the listener never fires. It looks like a fix and is inert.

Use **`react-native-keyboard-controller`**, which tracks the IME through
WindowInsets — the only mechanism that survives edge-to-edge:

```tsx
<KeyboardProvider>            {/* must wrap the app */}
  <KeyboardAwareScrollView keyboardShouldPersistTaps="handled" bottomOffset={96}>
```

It is native-only with **no web implementation**, so put it behind a platform
seam and let web use a plain ScrollView — browsers already scroll a focused
input into view. Verify the native library does not reach the web bundle.

Also set **`keyboardShouldPersistTaps="handled"`** regardless. Without it the
first tap while the keyboard is up only dismisses the keyboard, so the button
under your finger never fires and every submit appears to need two taps.

**Known remaining gap:** `bottomOffset` clears the *focused field*, not the
submit button beneath it. On an emulator that button can stay behind the
keyboard even with a generous offset. Emulator IME inset behaviour diverges from
real hardware — confirm on a device before concluding either way.

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

### "It flashes" / "something isn't drawn" when navigating
Users describe this as a rendering glitch. It usually is not: a live-data hook
that resets to `loading` on mount replaces the WHOLE screen with a spinner every
time you navigate — including the parts that did not change — then repopulates.

**Measure it before theorising.** Record the device and sample frames, then sort
by file size: a near-blank frame compresses to a fraction of a populated one.

```sh
adb shell screenrecord --time-limit 8 /sdcard/nav.mp4
adb pull /sdcard/nav.mp4 && ffmpeg -i nav.mp4 -vf fps=20 f_%03d.png
ls -lS f_*.png | tail          # smallest = blank; count them for the duration
```

Twenty consecutive frames at a quarter the normal size is a full second of blank
screen — not a transition problem, and no animation will fix it.

**Fix:** cache the last result per subscription and seed state from it on mount,
so returning to a screen you were just on renders immediately. Key the cache by
the query IDENTITY (label + the deps that define it) so a *different* query still
resets to loading — otherwise you reintroduce the far worse bug of showing one
query's data under another's heading. Evict on error so a failed listen cannot
be resurrected by a later mount.

### A submit button "does nothing" for seconds, so users tap it repeatedly
Firestore's `addDoc`/`updateDoc` promises resolve on **server acknowledgement**,
which can take many seconds on a phone. If the UI waits for that before clearing
the field or showing progress, the button looks dead.

Clear the input immediately and show a busy state; Firestore applies the write
locally, so the item appears on its own. Restore the text if the write actually
fails — losing what someone typed is worse than a moment of uncertainty. Disable
while in flight so repeated taps cannot post duplicates.

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

---

## How this stack fools you

Meta-lessons, each paid for by a confident wrong answer. The entries above are
facts; these are the habits that stop you generating new bugs of the same shape.

### Silent no-ops: code that runs, throws nothing, and does nothing
This stack is full of APIs that are *present* but inert in your configuration:

- `Keyboard` events under edge-to-edge — never fire
- `Switch`'s `thumbColor`/`trackColor` on react-native-web — ignored
- an empty value in `.secret.local` — not treated as an override
- a bundled workspace package left in `dependencies` — installed anyway

None of these error. **When a fix produces no visible change, first ask whether
the mechanism ran at all** — before concluding the fix was insufficient and
piling a second change on top. Prove the input reached your code (log the value,
assert it is non-zero) rather than inferring it from the output.

### Your own interaction can counterfeit the fix
A keyboard fix looked like it worked because the verification swipe scrolled the
button into view. The screenshot was real; the causal story was invented.

**Re-test without touching anything.** If confirming a fix requires you to
scroll, tap, or retry, you cannot attribute the result to the fix. Change one
thing, observe passively, and compare against a before-image captured the same
way.

### Web is not evidence about native, and an emulator is not a device
`react-native-web` resolves flexbox trees differently, so a screen that renders
perfectly in a browser can be blank on a phone. An emulator misreports IME
insets, so keyboard behaviour differs from real hardware.

**Reproduce on the surface that is broken.** A green web suite says nothing about
a native layout bug — the divergence *is* the bug.

### Read the reference implementation before designing a fix
A sibling project had already solved the keyboard problem with a native library,
had the dependency pinned, and carried a comment explaining exactly why the
obvious approach fails. Two failed deploys and one bogus fix came from designing
first and checking second. **If a working implementation of the same stack
exists, read its config and comments before writing anything.**

### "Deployed" is not "working"
Firestore indexes report definitions with no build state; a `CREATING` index
errors exactly like a missing one. Functions can be *created* while their Cloud
Run service is not. **Probe the behaviour** — run the query, invoke the callable
— rather than trusting a success message or a resource listing.

### Say what you did not verify
Several bugs here were reported fixed on the strength of a plausible mechanism.
The cost is not the wrong fix; it is that the next person trusts it. When the
architecture is right but the symptom is unconfirmed, **write that down** — in
the commit message, in the notes, to the user. An honest known-gap is cheaper
than a false all-clear.
