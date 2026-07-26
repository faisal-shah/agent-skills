---
name: expo-firebase-stack
description: Diagnose and avoid the recurring traps in Expo + react-native-web + Firebase JS SDK apps — Google sign-in failing only inside chat-app browsers, DEVELOPER_ERROR on Android, emulator data that "does not exist", stale Metro bundles, config plugins that silently do nothing in the bare workflow, module-resolution errors naming files that exist, native debug builds serving stale JS or an unset EXPO_PUBLIC flag, screenshotting a stale installed build, unauthenticated screenshots that verify nothing, unthemeable react-native-web controls, push notifications that deliver nothing while every visible part works, live-query races that make seeds and tests silently do nothing, and nightly "backups" that are really mirrors and protect against nothing. Use when building, debugging, deploying, or verifying an Expo app that shares one codebase across Android and web via react-native-web with Firebase for auth/Firestore/Functions.
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

### "Disable client sign-up" also blocks the FIRST federated sign-in
Auth → Settings → User actions → **Enable create (sign-up)** maps to
`client.permissions.disabledUserSignup`. It is easy to read as "stop strangers
self-registering with email/password". It is not that: it blocks **every**
client-side account creation, and a federated user's first sign-in *is* a
creation. Google sign-in then fails with **`auth/admin-restricted-operation`**
for legitimate users who have never signed in before, while existing users are
unaffected — so it looks like a broken new-user path rather than a setting.

It fails **before** any auth-create trigger runs: no user is created and the
trigger logs nothing. That pair — zero users AND zero trigger invocations —
is how you tell this apart from a trigger that deleted the account.

So **an app where a population self-onboards through an IdP cannot use this
setting.** Enforce it in the auth-create trigger instead, which needs a way to
tell the populations apart. A discriminator that works, if one population is
Admin-SDK provisioned: create those users **without a password**, and they have
**no provider at all** when the trigger fires. Anything already carrying
`password` at creation therefore came from the client SDK. (`onCreate` does not
fire again when a user later sets a password, so real accounts are never
mis-read.)

Blocking functions (`beforeUserCreated`) are the better mechanism — they reject
before the account exists rather than deleting it moments later — but they
require upgrading the project to Identity Platform.

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

### An optional callable field arrives as `null`, not missing
A client sends `{ classId: someState ?? undefined }` for "nothing selected". The
server guards with `if (d.classId !== undefined)` and rejects it as a bad value.

**The callable client serializes an explicitly-`undefined` property as `null`.**
The key is an own enumerable property, so it is encoded rather than dropped the
way `JSON.stringify` would drop it — and the wire format then cannot distinguish
"absent" from "explicitly nothing".

So on the server, **treat `null` as absent for every optional field**:

```ts
if (d.classId !== undefined && d.classId !== null) { /* validate */ }
```

and on the client, omit the key rather than setting it undefined:

```ts
...(classId ? { classId } : {})
```

This bites hardest on the empty-state path — the first record created, before
anything exists to reference — which is exactly the path a demo or a fresh
install takes and a happy-path test does not.

### A callable returns "internal", and the browser blames CORS
Three symptoms, one cause. The functions emulator **accepts connections on its
port before it has registered any function**. Until registration finishes, every
call 404s with `Function <name> does not exist`. A 404 carries no CORS headers,
so the browser reports *"blocked by CORS policy"*, and a Firebase callable
surfaces the whole thing to the UI as a bare `internal`.

Nothing points at the real cause: the app looks broken, the CORS message
suggests a config problem, and the emulator log says every function initialised
(it did — just later than the first call).

Waiting for the port is not waiting for readiness. Wait for a **known callable
to exist**:

```js
// 404 → not registered yet. Anything else → ready.
const res = await fetch(`http://127.0.0.1:5001/${projectId}/${region}/${knownFn}`,
                        { method: 'OPTIONS' });
if (res.status !== 404) ready = true;
```

The same symptom appears with a **leftover emulator from a killed run**: it holds
the port with nothing registered, so a fresh run talks to a half-dead process. If
a failure reproduces on stashed changes, it is environmental — check the ports
before reading your diff.

Free them **by port**, never `pkill -f firebase`: that pattern also matches the
killing script's own command line and the shell that spawned it.

```sh
ss -lptn "sport = :5001" | grep -oP 'pid=\K[0-9]+'
```

### Emulator hosts: use `127.0.0.1`, never `localhost`
The emulators bind IPv4 only, while `localhost` can resolve to IPv6 `::1` first.
The connection then fails before any response exists — which the browser again
reports as a CORS error, because there are no headers on a request that never
completed. Put the literal `127.0.0.1` in client config; keep `10.0.2.2` for the
Android emulator reaching the host.

### First deploy of a Firestore-trigger function: Eventarc permission denied
`Validation failed ... Permission denied while using the Eventarc Service Agent`
on the *first* trigger deploy in a project. The deploy enables Eventarc, but the
service agent's permissions take minutes to propagate. It is not a config error
and changing the config makes it worse. Wait 2–5 minutes and redeploy only the
failed functions.

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

**"Deployed" is not "ready," and neither is `READY`.** `firebase
firestore:indexes` lists definitions but no build state, and an index still
`CREATING` errors on use exactly like a missing one — ~4 minutes even on an empty
database. Worse, `gcloud firestore indexes composite list` can report **`READY`
for every index while queries still fail** with "that index is currently
building" for another minute or two (seen on the one collection that had
documents in it). **Poll the query itself, not the index state** — the query is
the thing you care about, and it is the only signal that cannot be early.

Read the true state:

```sh
curl -s -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  "https://firestore.googleapis.com/v1/projects/<project>/databases/(default)/collectionGroups/<coll>/fields/<field>"
```

## Offline persistence

### The JS SDK has NO persistent cache on React Native
`persistentLocalCache` (and the older `enableIndexedDbPersistence`) is built on
IndexedDB, which React Native does not have — so on native the Firebase **JS
SDK** falls back to a MEMORY cache. This is the same reason auth must be wired to
AsyncStorage with `getReactNativePersistence`: no web storage primitives exist.
(`@react-native-firebase` has native persistence, but it is a different library —
if you are on the JS SDK for web support, you do not have it.)

What that means for offline writes:
- **Within a running process**, the memory cache still queues writes made offline
  and flushes them on reconnect. "Do it offline, stay open, reconnect" works.
- **Across an app kill**, the memory cache is gone. A write queued offline and
  then force-killed before it synced is **lost** — and the optimistic local state
  is lost too, so the user reopens to find their action silently reverted. Web
  does not have this problem (IndexedDB persists across a page close).

Verify, do not assume, and the test is specific: mark the write offline, **force-
stop the app**, reopen online, and check the server. If the write is gone, you
need a backstop. (Confirmed on a real AVD: 0 rows on the server after the kill.)

The fix is NOT a bespoke sync engine. It is a thin **AsyncStorage outbox over the
same direct write**, native-only (a no-op on web where the cache suffices):
record the intent durably, fire the write, and forget it only when the write's
promise resolves (server ack — offline it never resolves, so the record
survives). On launch, replay whatever is left, scoped to the signed-in uid. Keep
it idempotent with a **deterministic document id**, so a replay overwrites rather
than duplicates — which also means you outbox the current-STATE doc, not an
append-only event log (replaying that would double entries).

That AsyncStorage survives the kill is already proven by auth staying signed in
across restarts — it is the same primitive.

## Cloud Storage and long media

Uploading files, streaming long audio/video, and reading media metadata each
hide a trap that only shows on device.

### Resumable-upload progress can exceed 100%
`uploadBytesResumable(...).on('state_changed', s => s.bytesTransferred / s.totalBytes)`
reads past `1.0` on React Native — ~140% seen — because the SDK re-sends a chunk
on a network hiccup and `bytesTransferred` climbs past `totalBytes`. The upload
itself is fine; only the number lies. **Clamp it:
`Math.min(1, bytesTransferred / totalBytes)`.** Web does not show this, so it
passes review on web and surfaces only when someone watches the bar on a phone.

### Going offline does NOT fail an upload — so you cannot test failure that way
`uploadBytesResumable` is *resumable*: drop the network mid-upload and it retries
and resumes when connectivity returns, finishing successfully (its retry budget
is minutes, not seconds). So "kill the network to test the failure path" is a
**false negative generator** — you conclude your error handling never ran when in
truth there was no error. To exercise a real failure, break something that does
not self-heal: block the *finalize/confirm* callable the client calls after the
bytes land (`page.route(... , r => r.abort())` in Playwright). That is also a
failure mode you genuinely have — bytes in Storage, no database record — so the
test is worth having for its own sake, and it fails fast instead of after the
retry budget.

### An upload SPANS the moment its database record starts existing
The usual safe ordering is: a callable creates the record and returns an id, the
client writes the object to Storage under that id, then a second callable
confirms it. That means a live listener on the record flips `null → set` **while
the upload is still running**. Anything rendered in a branch keyed on "does the
record exist" is therefore destroyed exactly when it is needed — most obviously
the progress bar, which unmounts the instant the upload starts, leaving the
"record exists but has no media" branch on screen: an error notice and a delete
button, for the entire duration of a perfectly healthy upload. **Own the upload
state above that branch**, and treat "exists but empty" as a normal, recoverable
state (mid-upload, failed, media removed) rather than an error. Related: give
that state a way *out* — if your API can clear the media for re-upload, the UI
must expose re-upload, or clearing it is a one-way door whose only escape is
deleting the record.

### Uploading a picked file on native: URI → Blob, not a File
A document/image picker on native returns a `file://` (or `content://`) **URI**;
the web `<input type=file>` hands you a `File`, which already IS a Blob. The
Storage SDK wants a Blob, so the two platforms cannot share the picker code —
put it behind a `.web` seam. On native, bridge the URI:
`const blob = await (await fetch(uri)).blob()` — React Native's Blob layer
resolves a local URI. If the picker returns a typeless blob, carry its declared
mime type or the upload records `application/octet-stream`:
`blob.slice(0, blob.size, mimeType)`.

### Reading media duration is itself a platform seam
To show a duration / draw a scrubber you need the media's length. Web decodes it
from an `<audio>`/`<video>` element plus `URL.createObjectURL(blob)`; **native
has neither of those APIs.** Use the audio library instead
(`createAudioPlayer({ uri })` + a `playbackStatusUpdate` listener reading
`status.duration`), which reports nothing until the media loads — so resolve on
the first status carrying a finite, positive duration, with a timeout fallback
that reads `player.duration` once more before giving up. Resolve `null` on
failure, never throw: a weird file must not block an otherwise-fine upload.

**The trap is what a null duration does downstream.** If a player derives its
scrubber range, remaining-time and listened-% from a STORED duration, a `null`
one does not just hide a label — it breaks the transport (0-length scrubber,
`-0:00`, a stuck progress bar) while the audio still plays. So capture duration
at UPLOAD on *every* platform and store it, rather than leaving it null on the
platform whose browser API is missing. Verify by PLAYING a file uploaded from
each platform — not by reading the list label, which looks fine either way.

### Long media: don't proxy through a function, don't hand out non-expiring URLs
Two independent rules that both bite only in production:
- **Streaming bytes through a callable dies on the function timeout.** A
  multi-hour file outlives the max function runtime, so playback stalls partway.
  Stream from Storage directly; never proxy the bytes through a function.
- **`getDownloadURL()` mints a token that NEVER expires.** If a leaked link must
  eventually stop working, that token is the one thing that rules it out. Mint a
  short-TTL **signed URL** from a callable that has already checked authorization,
  and re-mint it before expiry. Note an expired GCS signed URL returns **HTTP 400
  `ExpiredToken`, not 403** — a retry handler keyed on 403 will sail right past it.

### Background audio: there must be AT MOST ONE player, and stop it before removing
Once you enable background playback (`setAudioModeAsync({ shouldPlayInBackground:
true })` + the foreground-service permissions + POST_NOTIFICATIONS for lock-screen
controls), the audio player is kept alive by a foreground service — and two
things that are harmless in the foreground become orphaned-audio bugs:
- **`player.remove()` does NOT stop a playing background player.** Removing the
  object releases your handle, but a foreground-service player keeps producing
  sound. Teardown must **`pause()` first** (and drop the lock-screen session,
  e.g. `setActiveForLockScreen(false)`) *before* removing. A screen that unmounts
  without pausing leaves audio playing with no UI to stop it — and swiping the app
  away doesn't kill it either.
- **Nothing stops you creating a second player over the first.** If the player
  lives in a screen and navigation mounts the next screen before the previous
  one's cleanup runs (or a cleanup is skipped), you get two streams at once, and
  neither the lock-screen controls nor force-quitting can stop the orphan. Keep a
  **module-level single-player handle**: creating a player tears its predecessor
  down first, so at most one stream can ever exist. That guard is also the safety
  net for the missed-cleanup case the per-screen `useEffect` return can't cover.

Emulators can't prove this — audio focus is held at the module level regardless,
and a signed URL that points at `127.0.0.1` won't even stream to an AVD. Verify
the *lifecycle* instead: temporary `console.log`s in create/unload, driven via
adb and read from logcat, show teardown-then-recreate without a second live
player; the audible behaviour is a real-device check.

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

### A config plugin you added does nothing (bare workflow)

You add a plugin to `app.json`, rebuild, and the permissions, services or
entitlements it is documented to add are simply absent from the app.

**Config plugins only run during `prebuild`.** In the bare workflow — a
committed `android/` or `ios/` directory — `expo run:android` does NOT re-run
prebuild, so the plugin never touches the native manifest. Nothing warns you;
the build succeeds.

This is nastier than it sounds, because a half-configured native module often
*half* works. Background audio, for example, kept playing on an emulator with no
foreground service and no permissions at all — Android is lenient there — so
every local check passed while the shipped app would have been killed under
memory pressure on a real device.

```bash
npx expo prebuild --platform android --no-install
git diff android/app/src/main/AndroidManifest.xml   # confirm ONLY what you expected
```

Read that diff rather than trusting it. Plugins add things you did not ask for:
one added `RECORD_AUDIO` to a playback-only app because its `recordAudio` option
defaults to true, which is both a scary Play-listing permission and a review
question you do not want to answer.

Verify against the INSTALLED package, not the source manifest — the merged one is
what ships:

```bash
adb shell dumpsys package <applicationId> | grep -oE "android.permission.[A-Z_]+" | sort -u
adb shell dumpsys activity services <applicationId> | grep -E "isForeground|foregroundServiceType"
```

### Metro insists a module does not exist, and the file is right there

`The module could not be resolved because none of these files exist`, listing a
path you can `ls` and see.

Metro cached its resolution before the package was installed. Installing a
dependency while Metro is running does not invalidate that cache, and a native
rebuild does not either — the packager is a separate process with its own state.

Restart Metro with `--clear`. Worth suspecting **any** time a module resolution
error names a file that demonstrably exists.

### Stale config baked into a bundle
`EXPO_PUBLIC_*` is **inlined at build time**. Build with `--clear` when config
changes. Corollary: `EXPO_PUBLIC_*` can never hold a secret — anyone with the app
has it.

### A native DEBUG build ignores an `EXPO_PUBLIC_*` flag you did set
The app on the emulator behaves as if the flag is unset — no dev-only affordance,
pointing at the wrong backend — even though you exported it.

A native **debug** build carries almost no JS: it loads the bundle, and the
inlined `EXPO_PUBLIC_*` values, **from Metro at launch**. So the flag has to be
set in the environment that started *Metro* (`EXPO_PUBLIC_X=1 expo start`), not
when you built the APK — and Metro's transform cache can hand back an older
bundle. **Restart Metro with `--clear` and the vars set**, then relaunch. The APK
itself holds no `EXPO_PUBLIC_*` values to fix.

### You are screenshotting a build that is not your latest code
The running app shows behaviour that does not match the change you just made, and
you start debugging a fix that is actually already correct.

The installed build is stale. `expo run:android` printing **BUILD SUCCESSFUL is
not proof it installed** — if the emulator drops during the run (a shared AVD is
flaky), the install step never happens and yesterday's APK is still on the
device. Confirm what is actually installed before trusting any screenshot:

```bash
adb shell dumpsys package <applicationId> | grep versionName
```

Derive `versionName` from `app.json` so that number means something — a scaffold
default that never bumps makes "which build is this?" unanswerable, on the device
and in your crash reports.

## react-native-web

### A control ignores your theme colours
`Switch` ignores `thumbColor`/`trackColor`, and the RNW-specific
`activeThumbColor`/`activeTrackColor` are gone in 0.21 — it renders Material
teal. Build toggles from `Pressable` and views you control. Assume any RNW
control wrapping a platform widget may not be themeable, and confirm with a
screenshot rather than trusting the props.

### Two adjacent icon buttons and you keep hitting the wrong one
Reported as "you have to use the very tip of your finger" to tell two icons
apart — often a save/cancel pair, where the cost of a mis-hit is highest.

`hitSlop` does not enlarge an element. It paints an invisible margin **outside**
it, and neighbours' margins **overlap**: two icons 4px apart with 12px of
horizontal slop each share a 20px band belonging to both, and which one receives
the touch is arbitrary. The gap being smaller than the combined slop is the whole
bug, so it appears exactly where controls are tightest and matters most.

Give the control a real laid-out box instead — `minWidth`/`minHeight` of 44 with
the ink centred inside it. Laid-out boxes cannot overlap, so adjacent targets are
always unambiguous, and 44 is the platform accessibility minimum rather than a
number that felt right. Rows of these then want a SMALL gap, not a large one: the
separation is already inside the target, and keeping the old gap can push a
one-row control bar past a phone's width.

Audit for this by measuring, not squinting: assert the rendered boxes are 44×44
and that the gap between them is ≥ 0.

### A paged horizontal ScrollView paints the WRONG page first
Symptom: coming back to a screen that restores a remembered page, the header
names one page while the body shows another — and if that other page is empty it
reads as "my data is gone".

Restoring page state is synchronous, restoring scroll position is not. A
`scrollTo` from `onLayout` (or deferred a frame) runs after a paint, so the first
frame shows offset 0 under a header that already says page N. `contentOffset`
looks like the fix but is only reliably honoured on **mount** — setting it on an
already-mounted ScrollView is not applied on Android.

What works: measure the width on a **wrapper**, mount the ScrollView only once
the width is known, scroll from **`onContentSizeChange`** (the first moment the
pages exist and a scroll can land), and keep it invisible until it is on the
right page — a blank frame beats a wrong one. Guard the reveal on "is there
actually a page to restore", or a remembered index that no longer exists (columns
deleted since) leaves the screen permanently blank.

### Verifying a horizontal pager by dumping text LIES to you
`uiautomator dump` returns every page of a horizontal ScrollView, on-screen or
not, because they are all in the hierarchy. Grepping the dump for a column's text
"finds" it regardless of scroll position, so a broken pager looks fine and a
fixed one looks broken.

Check the node **bounds** — an off-screen page collapses to zero or negative
width — or take a screenshot and look. This is the same class as a green web
suite proving nothing about a native layout: the check ran, and measured
something other than what you asked.

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

### A hand-rolled slider/drag works on web but freezes on device
A custom `PanResponder` drag bar (slider, scrubber) inside a `ScrollView` is
fine on web — the pointer maps to a mouse and nothing competes for it — and
fails on device: a real finger-drag always has a vertical component, the native
ScrollView claims the gesture, the pan terminates, and the thumb freezes while
the finger keeps moving. `onPanResponderTerminationRequest: () => false` does not
reliably override the *native* ScrollView on Android. Stop hand-rolling the
gesture and use the native **`@react-native-community/slider`**, which consumes
touch at the platform level. Two things that bite when you switch:
- It has **no web build** (no `browser` field, no `.web.js`) — importing it into
  a shared component breaks the web bundle. Add a `Scrubber.web.tsx` seam that
  keeps the PanResponder version (which worked on web) or an `<input
  type="range">`.
- After a programmatic seek, the player keeps emitting the OLD position for a
  beat; bind the slider to the shown position and ignore progress ticks until the
  player reports a value near the seek target, or the thumb snaps backwards the
  instant you release it.

### You cannot verify a drag gesture with `adb` — it can't simulate an RN pan
`adb input swipe` and even discrete `adb input motionevent DOWN/MOVE/UP` do NOT
produce a faithful continuous React Native pan: `gestureState.dx` stays near zero
or oscillates instead of accumulating, so a drag "test" lands nowhere near the
target and looks broken even when the code is correct (and looks fine even when
it isn't). Do not trust adb to prove a JS pan works or fails. A *native*
component (the slider above) does respond to `adb input swipe` because it handles
raw touch — which is one more reason to prefer it: it's the only version you can
actually drive headlessly. For a JS PanResponder, the ground truth is a real
device (or logging the `dx`/grant/terminate sequence from logcat to see what the
responder actually received).

### A wrapping button row CRUSHES its buttons on device, but not on web
A row of controls styled `flexDirection: row, flexWrap: wrap` with items at
`{ flexGrow: 1, flexShrink: 1, flexBasis: 150 }` looks correct on
react-native-web at every width — items either share a line evenly or wrap. On
device, Yoga will instead **squeeze** a line that does not quite fit, and it does
not distribute the squeeze evenly: one button ends up a fraction of its
neighbour's width, narrower than its own label, which then breaks *mid-word*
("Publ / ish"). **Set `flexShrink: 0`** on the row items: a line then either fits
or wraps, and both are readable. Keep `flexGrow: 1` so a lone button still fills
the row, and add `maxWidth: '100%'` for the one case shrink was covering (a basis
wider than the container on a very narrow screen).

Two things make this expensive to find: it does not reproduce under
react-native-web at *any* viewport width, and it is metric-dependent enough that
you may not reproduce it on your emulator either (density and font-scale sweeps
can all come back clean while a real phone shows it). When you cannot reproduce
the trigger, **fix the mechanism** — with shrink disabled a control cannot be
narrower than its basis regardless of *why* the line did not fit — and say
plainly that the trigger is unconfirmed.

### Button labels break mid-word at large accessibility font sizes
`allowFontScaling` is on by default, so a user at Android's largest font setting
(scale 2.0) renders your 15sp label at 30sp. A single word wider than the button
does not shrink or ellipsise — it **breaks mid-word**: "Submit att / endance".
Fix it on the shared button primitive, not per screen:
`numberOfLines={2} adjustsFontSizeToFit minimumFontScale={0.7}`. Two lines lets a
multi-word label wrap at a word boundary (which is fine and readable); the font
only scales down when a single word still will not fit. Do not simply pin
`numberOfLines={1}` — that truncates, and do not disable font scaling, which is
an accessibility setting the person deliberately chose. Sweep `adb shell settings
put system font_scale 2.0` before shipping any dense control-heavy screen.

### Emoji arrows ignore text colour
`◀`/`▶` render as colour glyphs. Use text-presentation characters (`‹`, `›`, `▾`)
or draw them.

### Branch layout on WIDTH, not platform
A tablet deserves the desktop layout; a narrow window deserves the phone one.
Treat drag-and-drop as a *capability* layered on the wide layout, not a platform
feature.

### A reorderable list wants a drag handle, not up/down buttons
When the *order* of a list is user-controlled (board columns, a sortable set of
options), reorder it by **dragging a handle**, not with per-row ↑/↓ buttons. The
buttons are one tap per position, read as unfinished, and don't scale. This stack
ships **no gesture library** (no reanimated / gesture-handler — a deliberate
omission), so hand-roll the drag rather than pulling one in: an HTML5-drag
`.web.tsx` (`draggable` + `onDragStart/onDragOver/onDrop`, reusing the board's
card-drag pattern) and a PanResponder `.tsx` sibling, both with a
`drag-indicator` handle. A short list (a handful of rows, fixed row height, no
nested scroll) is very hand-rollable; measure one row, translate the dragged one,
swap indices past the half-row line, commit on release. Adding
reanimated+gesture-handler for this would be a major architectural change — don't,
without a deliberate decision.

### The desktop view is a phone screen stretched sideways
A phone-first app opened on a laptop looks amateurish: full-width primary buttons
become bars all the way across the window, list rows are wide mostly-empty
strips, and a single capped column strands the content in whitespace. Nothing is
"broken" — it is just the phone layout with the width turned up, and it reads as
unfinished on the monitors most desk users have.

The shapes that are right on a phone are wrong on a desktop, so make them
**responsive to width**, not fixed:

- **Buttons.** Full-width is a good primary-action shape on a phone; on a wide
  screen a standalone button should size to its label. Bake this into the button
  primitive (`alignSelf: isWide ? 'flex-start' : 'stretch'`), so every screen is
  fixed at once — a button inside a row is already content-width, so only the
  stretched column-child case changes. Keep a `block` escape hatch: the rare
  single-action screen (sign-in) whose one primary button should still span its
  container looks stranded when that button shrinks to its label.
- **Reading columns vs. grids are different maximums.** Text and forms want a
  *narrow* column (~640) so lines stay readable and fields aren't stretched;
  card LISTS want a *wide* column and a **grid** that flows into as many columns
  as fit (`flexWrap` + `flexBasis` ~250px, capped so a lone last card doesn't
  stretch), collapsing to one column on a phone. A single `maxWidth` for
  "content" cannot serve both — give the screen wrapper a `width` variant
  (`read` / `list` / `full`).
- **Native form controls size to their widest option, not the current one.** A
  `<select>` reserves collapsed width for its longest `<option>`; a short current
  value then sits in a box sized for the longest one. `field-sizing: content`
  makes it hug the selection (progressive enhancement — it no-ops on older
  engines).
- A persistent nav bar changes what each screen needs: a tab-root screen reached
  only from the bar is never pushed, so its per-screen Back button is dead and
  sits stranded — drop it.

You cannot reason your way to "it looks designed" — **open it at a real desktop
width** (1400–1600 in Playwright) *and* at a phone width, and look. The 840px
column that looks fine in a review is the tell.

## Observability

### Test runs pollute the production error project
Gate reporting on the same flag that points the app at emulators. Beyond wasting
quota, the browser SDK wraps `fetch` for breadcrumbs and beacons to an ingest
host a sandbox cannot reach — enough to stall a sign-in flow and fail a suite.

### Do not run `@sentry/wizard` on a repo with committed native directories
It rewrites native files and metro config and writes a `sentry.properties`
containing a real auth token. Wire the SDK by hand.

### Web source maps: inject debug ids, upload, then STRIP before deploy
`expo export` emits no source maps unless you pass `--source-maps`, so production
stack traces are minified by default. The robust upload path uses **debug ids**
(no release/version coordination): `sentry-cli sourcemaps inject <dist>` stamps a
matching id into both the JS and the maps, then `sentry-cli sourcemaps upload`.
Do it as the hosting predeploy so every deploy is covered.

Two traps:
- **Delete the `.map` files from the deploy dir after uploading.** Otherwise
  Firebase Hosting serves your source publicly. The shipped JS keeps its debug
  id, so events still symbolicate against the maps in Sentry.
- **A `.map` URL on the live SPA returns `200`, not `404`** — the `** →
  /index.html` rewrite catches the missing file and serves HTML. Verify maps are
  gone by the **content-type** (`text/html` = fine), never the status code. The
  same rewrite hides any missing-asset 404 behind a 200.

An **organization** auth token (`sntrys_…`, org-scoped) uploads to every project
in the org — reuse one across apps rather than minting per project. Point
`sentry-cli` at it with `SENTRY_PROPERTIES=<gitignored sentry.properties>` and
override `--project` per surface; the token never has to pass through your shell.

### `@sentry/react-native` source maps need a release build AND the Gradle plugin
Native upload only runs on `assembleRelease`, and only if the Sentry Gradle
plugin is applied — which the config plugin does at `prebuild`. In the bare
workflow (committed `android/`, no prebuild) a `sentry.properties` alone uploads
nothing. Runtime error *reporting* still works; only symbolication waits. This is
a first-release concern, not a first-wire one.

### Serverless events never arrive
The instance can freeze the moment the handler resolves. `await Sentry.flush(...)`
before returning. Exclude expected domain errors (`HttpsError`) or real defects
drown in users mistyping things.

### Expected user actions must not be reported as errors
Closing a Google sign-in popup raises `auth/popup-closed-by-user`. If the screen
catches it and the catch reports, "someone changed their mind" arrives in the
issue stream looking like a defect.

Swallow the cancellations on web — they are not failures:

```ts
if (code === 'auth/popup-closed-by-user' ||
    code === 'auth/cancelled-popup-request' ||
    code === 'auth/user-cancelled') return;
```

The native Google Sign-In SDK has always had the equivalent
(`SIGN_IN_CANCELLED`, `IN_PROGRESS`), so the two seams drift apart unless you
check both. Same principle as excluding `HttpsError` server-side: an expected
domain outcome is not a defect.

**This matters more once reporting actually works.** An issue stream full of
benign events is one nobody reads, and then the real report arrives and gets
scrolled past — the same failure mode as a flaky test suite teaching everyone to
re-run it.

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

## Backups and disaster recovery

### A nightly export is a mirror, not a backup
The usual first attempt — a scheduled function that rewrites a Sheet/CSV/bucket
copy of the data every night — protects against nothing. It **clears and
rewrites**, so a deletion is faithfully copied over the only other copy you have,
typically within a day. There is no history to roll back to.

Three questions expose the difference:

- **Does it keep old versions?** Overwriting one destination = one restore point,
  and it is always the *current* (possibly broken) state.
- **Does it cover everything?** Exports built for reporting usually filter —
  approved/published/non-draft rows only — and cover one collection. A restore
  needs users, roles, config and the in-flight records too.
- **Would it survive the thing you fear?** An accidental mass delete, a bad
  deploy, a compromised admin account. If the answer is "the export would copy
  it," it is a convenience feature, not a backup.

Fix: use Firestore's native protection (below) and let any export be what it
actually is — a reporting artifact.

### Two native layers, with very different jobs
Both are Google-managed settings, no code to maintain, and they compose. Note
that **none of this needs a client change** — the whole plan is database settings
plus one backend job, so it never gates on shipping an app release:

| Layer | Window | Job |
|---|---|---|
| **PITR** | rolling **7 days** | rewind to any microsecond — "someone deleted it this morning" |
| **Scheduled backups** | **14 weeks maximum** | "we noticed in September that something broke in July" |

```sh
firebase firestore:databases:update "(default)" --point-in-time-recovery ENABLED
firebase firestore:backups:schedules:create \
  --recurrence WEEKLY --day-of-week MONDAY --retention 98d
# inspect
firebase firestore:databases:get "(default)"
firebase firestore:backups:schedules:list
firebase firestore:backups:list
```

14 weeks (98 d) is the ceiling — Firestore will not retain a backup longer.
Beyond that you must export to Cloud Storage and manage retention yourself. Also
consider `--delete-protection ENABLED`, which blocks deletion of the whole
database.

Weekly-at-max-retention pairs better with PITR than daily does: PITR already
covers the recent window at far finer granularity, so spend the backup schedule
on *reach* rather than duplicating the last seven days.

### PITR and backup data are excluded from the free tier
Firestore's free tier includes stored data; **PITR data and backup data are
explicitly excluded** and require billing enabled. For a small dataset the bill
is a fraction of a cent, but it is not literally zero — expect a new line item,
and do not assume "we're on the free tier" means these are free.

### A restore creates a NEW database — and you cannot reuse the old id
`firebase firestore:databases:restore --database <new-id> --backup <name>`
restores into a *different* database, and the docs are explicit: **"You cannot
use a database ID that is already in use."** There is no restore-in-place. Same
for a PITR recovery.

Two consequences people discover mid-incident:

- **Backups do not contain your security rules, IAM, or TTL policies.** A
  restored database comes up needing all of them reapplied. If rules live in the
  repo and deploy from it (they should), that is one command — otherwise it is a
  scramble at the worst possible time.
- **Do NOT plan to "just repoint the app" — that instinct is wrong for a mobile
  stack.** Repointing the web is a redeploy; repointing an installed Android app
  is a new build that **every user has to install**. Your recovery time becomes
  an app-store round trip.

So for a stack with installed clients, prefer bringing the data back to the id
the clients already use: restore to a scratch database → verify → **managed
export it → import into the original database id**, then delete the scratch one.
Clients never notice. Note that import **merges by document id**: it recreates
what was deleted, but it does not remove junk that was added, so it fixes a
deletion cleanly and a corruption only partially.

Rehearse this once against a throwaway project. A restore path nobody has walked
is a hope, not a plan — and the step that surprises people is not the restore, it
is discovering the destination id can never be the one their app is configured
for.

### Retention is worthless if nobody notices in time
The failure that beats a 14-week window is specific: **data breaks just before a
quiet period** — a holiday, a seasonal lull — so every subsequent backup captures
the already-broken state, and by the time someone looks, the last good backup has
aged out. Extending retention is the expensive lever. Noticing sooner is the
cheap one: detect within days and even a modest window is generous.

A small daily canary function covers it:

- **Count documents per collection with `count()` aggregations**, not full reads
  — `db.collection(name).count().get()` bills roughly one read per 1000 docs, so
  watching a whole database costs almost nothing.
- **Store the counts in a server-only doc** (e.g. `meta/health`) and compare
  against the previous run. Deny all client access in rules — it is operator
  state, not app data.
- **Set tolerance per collection, not globally.** Some collections should never
  shrink (config/lookup rows your rules forbid deleting; user records removed
  only by deliberate admin action) — there, *any* drop is a signal. Collections
  where users routinely delete their own rows need a threshold like
  `max(floor, fraction × previous)`: the floor stops a tiny dataset alerting on
  routine tidying, the fraction keeps it meaningful as data grows.
- **Always re-baseline**, including on a run that alerted — otherwise one bad day
  alerts forever against a frozen baseline.
- **Send a Sentry cron check-in** (`captureCheckIn` with a `monitorConfig`, which
  upserts the monitor so there is no console setup). This is the part people
  skip, and it is the most valuable: a job that has silently stopped never
  reports its own failure. Passing the schedule as `monitorConfig.schedule` lets
  Sentry alert on a *missing* check-in.

Keep the comparison logic pure (`(previous, current) => findings`) and unit-test
the policy exhaustively; keep the counting and the doc write in a thin wrapper an
emulator test can drive. Known limitation worth writing down: run-to-run
comparison catches sudden loss, not a slow bleed of a few documents a day — which
is the right trade, because accidents and bad deploys are sudden.

This is an operator signal, not a UI feature. "Entries fell 40%" is not something
a user in the app can act on.

## Push notifications (FCM)

### Nothing is delivered; the functions log success and no error appears anywhere
The classic shape here: the **send path is complete and the registration path
was never written**. The server reads each recipient's device tokens, finds an
empty list, and returns early — which is a success, not an error. The in-app
inbox, per-event preferences and mute controls all work, so the feature looks
finished from the outside, including to whoever builds the next thing on top.

**Verify the token exists before debugging delivery.** Read a real user document
in the console. If there are no tokens, nothing downstream matters.

### Registered a token, still nothing: Expo token vs device token
`getExpoPushTokenAsync()` returns an `ExponentPushToken[…]` that only Expo's push
service can deliver to. The **Firebase Admin SDK** (`getMessaging().send*`) needs
the native FCM token from `getDevicePushTokenAsync()`. Both "work", both store a
plausible string, and the mismatch surfaces only as silence.

Pick one delivery path and make the client and server agree on it.

### Bare workflow: `googleServicesFile` in `app.json` does nothing
`app.json` android config is consumed by **prebuild**. With a committed
`android/` directory nobody runs prebuild, so the setting is decoration. FCM then
has no project to register against and token requests fail or return nothing.

Three things must physically exist in the repo:

```
android/app/google-services.json                         # the file itself
android/build.gradle:      classpath 'com.google.gms:google-services:x.y.z'
android/app/build.gradle:  apply plugin: 'com.google.gms.google-services'
```

Confirm the build actually consumed it — the plugin generates resources, so
their absence is proof:

```bash
ls android/app/build/generated/res/processReleaseGoogleServices/values/values.xml
```

Keep `googleServicesFile` in `app.json` anyway, so a future prebuild agrees with
the committed files instead of silently diverging.

### Store tokens as a subcollection, never an array field
`users/{uid}/pushTokens/{token}` — the token is the document id.

An array field makes two devices registering at once a read-modify-write race,
and to let someone manage their own tokens you have to allow writes to a field
on their user document, which sits next to fields rules must protect. A document
per token cannot collide, deduplicates by construction, and is scoped by a rule
that grants nothing else:

```
match /users/{userId}/pushTokens/{token} {
  allow read, write: if isSignedIn() && request.auth.uid == userId;
}
```

`isSignedIn`, not `isActive`: **registration happens at sign-in, before an
approval workflow has approved anyone.** Gate the *send*, not the registration —
holding a token grants nothing on its own.

Nobody else may read the collection either, admins included: which devices a
person carries is not administrative data.

### Unregister on sign-out
A push targets the **device**, not the session. Skip this and a shared or
handed-on phone keeps receiving the previous account's notifications — a
disclosure, not an annoyance. Capture the uid *before* clearing session state;
the unregister needs to know whose token to remove.

### Tokens accumulate forever unless you prune them
Sign-out removes a token. An uninstall, a data wipe, or a factory reset does not
— that token stays until something deletes it, and every later send to that
person carries a growing tail that can only fail.

Delete on the response, and only on the two codes that actually mean *gone*:

```ts
const dead = res.responses.flatMap((r, i) =>
  r.error?.code === 'messaging/registration-token-not-registered' ||
  r.error?.code === 'messaging/invalid-registration-token' ? [refs[i]] : []);
```

Quota, unavailable, and internal errors are transient — pruning on those
unregisters working devices.

### A new `EXPO_PUBLIC_*` value never reaches the bundle
`EXPO_PUBLIC_*` is **inlined at build time and cached**. A module compiled before
the variable existed keeps the stale inlined value — normally `undefined` —
across repeated clean exports, because `dist/` is the output and not the cache.
The feature then behaves exactly as it does with no value configured, while the
code reading it is correct.

`expo export --clear`, and delete `.expo`.

Verify by grepping the export for the literal value, not by trusting the build:

```bash
grep -rc "<the value>" dist/_expo/static/js/web/*.js   # 0 means it never arrived
```

If a *different* `EXPO_PUBLIC_` var is present in the same bundle, env loading
works and the cache is the culprit. This is the stale-bundle trap wearing
different clothes — see "A UI change appears to have no effect".

### Web push needs two extra things and is inert without either
A **VAPID key** (Firebase console → Cloud Messaging → Web Push certificates) and
a service worker at `/firebase-messaging-sw.js`. A browser cannot be woken
without one.

Make the absence of the key an explicit early return rather than something that
throws mid sign-in. Half-configured web push should do nothing, visibly by
design, while native keeps working.

### What you cannot verify yourself
No emulator delivers a push. FCM has no emulator, and an Android emulator without
Play services will not receive one. Registration, rules and pruning are all
testable; **arrival is not**. Say so explicitly rather than reporting the feature
as done.

## Dead-code and dependency audits

### Every platform seam reads as dead code
A dead-code tool (knip, ts-prune, depcheck) resolves imports. It does not know
that the **bundler** picks `foo.web.ts` over `foo.ts` by filename, so every
`.web.ts(x)` in the project is reported as an unused file, and anything only
those files import is reported as an unused export or dependency.

Three failure modes, all of which look like real findings:

1. **Seam files are unused.** Add every `*.web.ts(x)` as an entry point, plus
   anything else the bundler or a runtime loads by convention rather than by
   import: `babel.config.js`, `metro.config.js`, a service worker under
   `public/`, CLI scripts.
2. **An export used only from a seam looks unused.** Grep across `.ts` *and*
   `.tsx` and typecheck before deleting. Deleting on the strength of a
   report-plus-hasty-grep is how a live export gets removed.
3. **"Unused dependency" is not "removable".** Packages consumed by something
   other than an import will always look unused: a babel plugin, a peer
   dependency of a library you do use, the browser driver behind an e2e script,
   the web build of an SDK used only in a seam file. Check *why* it is there
   before removing it.

Two more shapes worth knowing:

- **A workspace package deliberately absent from `functions/package.json`**
  (because the bundler inlines it — see the Cloud Build entry) is reported as an
  *unlisted* dependency forever. Suppress it explicitly, or someone will
  helpfully re-add the declaration and break the deploy.
- **Exported types used only inside their own file** are usually not cruft: they
  name the parameter or return of an exported function, i.e. they document a
  public surface. Un-exporting them is churn, not cleanup.

Finally, a judgement no tool makes: **some unused code marks a missing feature
rather than dead weight.** If deleting it would erase the only trace of a
user-facing gap, fix the gap instead.

### Grep can silently skip a source file
A single control byte — a raw NUL used as a separator inside a template literal,
say — makes `file` call the source "data" and git diff it as binary. **grep then
skips the whole file and reports no matches**, which during an audit reads as
"nothing uses this".

A verification tool that returns "no matches" for a file it cannot read is worse
than no tool at all. Write control characters as escapes (`\u0000`): identical
runtime value, readable source. Worth a CI guard, since nothing else complains.

## Testing and seeding

### "Verified by screenshot" — of the one screen that proves nothing
You captured a screenshot, it looked right, you shipped, and the bug was on a
screen you never saw.

The sign-in screen is the only screen an unauthenticated screenshot can reach,
and it exercises almost none of the app — no board, no forms, no empty states, no
lists. A green sign-in shot is not evidence about any of them. This bites hardest
for changes that touch *every* screen (a theme, a shared component): the one
screen you can trivially capture is the least representative.

To look at the real screens, get **past** auth against the emulators: a
`__DEV__`-only sign-in row (rendered only when pointed at the emulators) lets a
Playwright/adb script click a seeded user, then seed data by driving the UI, then
screenshot the authenticated screens — board, card, settings, the empty states.
Correct values in the token/source file survive right up until you look at the
rendered screen; layout gaps and contrast misuse both pass every "the code is
right" check and only appear here.

### The native screenshot is of a different app entirely
You "verified on native": launched the app, screenshotted, it looked right — but
it was a *sibling app* on the same emulator, fully rendered, counterfeiting
success.

`adb shell monkey -p <package>` (and `am start`) with a wrong or nonexistent
package name **silently launches nothing** and still exits 0. Whatever was already
foregrounded — a sibling app from another project sharing this emulator — stays on
screen, and the screenshot looks like a clean success. The package id is easy to
get wrong (the human-facing name and the applicationId rarely match). Two
compounding traps: a debug build does **not** reliably red-screen when it can't
reach *its* Metro — if a sibling project's Metro holds the shared port it will
serve that project's bundle into your app shell, or a stale cached bundle renders;
and a multi-line launch command whose newlines collapse into spaces can silently
root Metro at the repo root instead of the app dir (its bundle 404s on `./index`).

Prove the mechanism: confirm the **foreground package** is yours
(`adb shell dumpsys activity activities | grep -i mResumedActivity`), and confirm
**your** Metro logged the bundle (`… Bundled … app/index.ts (N modules)`) — not
just that *a* Metro answered `/status`. Only then trust the pixels.

### Grepping a release bundle for a string gives FALSE NEGATIVES (Hermes UTF-16)
Verifying that a fix actually shipped by unzipping the APK and grepping
`assets/index.android.bundle` is a good instinct, and it will lie to you. Hermes
stores a string containing **any** non-ASCII character — an em dash, a curly
quote, a `…`, an accent — as **UTF-16**, so an ASCII `grep` cannot match it. Two
strings added in the same commit give opposite answers purely on punctuation, and
the natural reading is "my fix is missing from the build". Search both encodings
before believing it:

```python
data = open('index.android.bundle','rb').read()
data.count(s.encode('utf-8')), data.count(s.encode('utf-16-le'))
```

Also do not build the pattern with bash `$'…\x00…'` — bash truncates a string at
the first NUL, so the pattern silently collapses to its first character and
"matches" everywhere (implausibly high counts are the tell). And note what this
check can and cannot prove: a string being *present* does not mean its code is
reachable — dev-only UI is compiled into release bundles too, and what actually
gates it is the build-time flag substitution (an absent `EXPO_PUBLIC_*` **name**
means it was inlined and folded, which is the thing worth asserting).

### A seed or test silently did nothing, repeatedly
Duplicate records, or an approval loop that approved nobody.

**A live query returns empty before it returns data, and empty is
indistinguishable from absent.** Sampling the UI immediately after navigating
gets the empty state, so an "already exists?" guard says no and creates another.

Wait for the list to *render* before deciding something is absent, and verify
against the database directly rather than the UI.

### A check that asserts on ABSENCE passes when the query is broken
The most dangerous test shape in this stack: fetch a list, assert the bad thing
is not in it.

Every failure of the fetch — wrong endpoint, wrong field name, an error body, an
auth failure — produces *no items*, which is exactly what "the bad thing is gone"
looks like. The check then passes forever without ever exercising the mechanism.

A real example: verifying that an auth-create trigger deleted a self-registered
account, by polling the Auth emulator's
`/emulator/v1/projects/<id>/accounts` and asserting the email was absent. That
endpoint is **DELETE-only**; the GET returned
`{"message":"Method GET not allowed"}`, so `userInfo` was `undefined`, the array
was empty, and the check passed unconditionally — including against a build with
the protection deliberately removed.

Two habits that catch it:

- **Assert on a positive fact instead.** Don't ask "is the account absent from
  this list" — *use the credential* and require the specific error
  (`EMAIL_NOT_FOUND`). A wrong endpoint then fails the check instead of passing
  it, and the error string is proof the request was understood.
- **Mutate the thing under test and watch the check go red.** This is the only
  way to distinguish a passing check from a vacuous one, and it costs one run.
  Any assertion of the form "X is not present" is worth this treatment.

### A test fails intermittently on a race it created itself
Waiting for condition A and then asserting on condition B in the same tick. A
trigger that deletes an auth user may still have a document write in flight; the
auth record is gone, the assertion runs, and the doc exists for a few more
milliseconds.

The assertion is about what **survives**, not about a moment — so poll for it:

```ts
await waitUntilGone('no user doc to remain', async () =>
  (await adminDb().doc(`users/${uid}`).get()).exists);
```

Re-run a suspected flake several times before and after the change. One green run
does not distinguish a fix from luck.

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
- `app.json` native config in a bare workflow — never read without prebuild
- a push send to an empty token list — returns success

None of these error. **When a fix produces no visible change, first ask whether
the mechanism ran at all** — before concluding the fix was insufficient and
piling a second change on top. Prove the input reached your code (log the value,
assert it is non-zero) rather than inferring it from the output.

### A feature can be complete except for its last link, and look finished
Push had a send path, an inbox, preferences, mute controls, and rules — and no
device ever registered a token. Every visible part worked. Nothing errored.

**For any end-to-end feature, name the links and check each one has code that
runs**, from the trigger to the thing a person actually sees. The link most
likely to be missing is the least visible one, and the parts that do work are
what stop anyone from asking.

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
