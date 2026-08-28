---
name: expo-firebase-stack
description: Diagnose and avoid the recurring traps in Expo + react-native-web + Firebase JS SDK apps — Google sign-in failing only inside chat-app browsers, DEVELOPER_ERROR on Android, emulator data that "does not exist", stale Metro bundles, config plugins that silently do nothing in the bare workflow, module-resolution errors naming files that exist, native debug builds serving stale JS or an unset EXPO_PUBLIC flag, screenshotting a stale installed build, unauthenticated screenshots that verify nothing, unthemeable react-native-web controls, push notifications that deliver nothing while every visible part works, an Android permission prompt raised at the worst possible moment because nothing refuses it, a permission screen that goes stale the moment the person leaves to fix the setting it named, live-query races that make seeds and tests silently do nothing, and nightly "backups" that are really mirrors and protect against nothing. Use when building, debugging, deploying, or verifying an Expo app that shares one codebase across Android and web via react-native-web with Firebase for auth/Firestore/Functions.
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

## Setting up a machine

`tools/bootstrap-linux.sh` installs the whole toolchain on a fresh Debian/Ubuntu
x86_64 box — Node 22, JDK 17 **and** 21, the Android SDK/NDK/AVD, gcloud, the
Firebase CLI, sentry-cli, Playwright + Chromium, jq, lsof, pip — **entirely under
`$HOME`, with no root**. It is idempotent, so re-running it repairs or upgrades.
`tools/check-host.sh` answers "can this box actually do Android?" and is worth
running on a candidate host *before* migrating to it.

```sh
tools/check-host.sh                              # verdict + what is missing
tools/bootstrap-linux.sh --repo ~/src/my-app     # install everything
tools/bootstrap-linux.sh --self-test             # verify, install nothing
```

The seven traps that make a fresh machine cost a day, all of which the script
already handles:

### `node: command not found` from a script, but not from your shell
Debian's stock `~/.bashrc` begins with a guard that **returns early when the
shell is not interactive**. Append your `PATH` setup to the bottom of `.bashrc`
and it works when you type commands and silently does nothing for every script,
cron job and agent tool call. Hook the environment file into **both**
`~/.profile` and `~/.bashrc`, and guard it against double-sourcing so `PATH`
does not accumulate duplicates. Note a bare `bash -c` reads neither file.

### Chromium exits immediately: `libnspr4.so: cannot open shared object file`
Playwright downloads its own Chromium, which needs no root — but that binary
links against ~90 Debian libraries a minimal image does not carry, and
`playwright install-deps` is an `apt-get install` that does.

**You do not need root for this.** `apt-get download` and `dpkg-deb -x` both work
unprivileged, so the libraries can be unpacked into a directory under `$HOME` and
found through `LD_LIBRARY_PATH`. Ask Playwright for the list rather than
hardcoding one:

```sh
npx playwright install-deps --dry-run chromium   # prints the exact packages
```

The same staging fixes the Android emulator, which dies at
`Could not open libX11-xcb.so.1, give up` for the identical reason.

### A missing `lsof` turns port guards into no-ops
Dev scripts commonly free ports with `lsof -ti:PORT | xargs kill`. When `lsof`
is **absent** that pipeline returns empty and exits 0 — so the script reports the
port clear while a stale dev server keeps serving yesterday's bundle. A missing
tool that converts a check into a silent pass is worse than no check. Install
it, and prove it reports a listener you started on purpose.

### `tar` cannot unpack Node: `xz: Cannot exec`
Minimal images often lack the `xz` binary, and `tar -xJf` shells out to it.
Node's Linux tarball is `.tar.xz`. `python3 -m lzma` is always there when
python3 is; likewise `python3 -m zipfile` when `unzip` is missing, which the
Android command-line tools need.

### `pip install --user` refused: externally-managed-environment
Debian 12+ ships PEP 668. `--break-system-packages` sounds alarming and is not:
with `--user` it only ever writes to `~/.local`. On an image with no pip at all,
bootstrap it from `get-pip.py` the same way.

### Android SDK tools ignore `$HOME`
`avdmanager` reported an AVD as already existing inside a scratch `HOME` that
contained no AVD at all — it had read the *real* home. The JVM resolves
`user.home` from the **passwd entry**, not the environment:

```sh
env -i HOME=/tmp/scratch java -XshowSettings:properties -version 2>&1 | grep user.home
#     user.home = /home/you          <- not /tmp/scratch
```

So `HOME=... some-android-tool` does not isolate anything, and a container, CI
job or sandboxed test that relies on it silently reads and writes the wrong
directory. Set `ANDROID_AVD_HOME` (and `ANDROID_SDK_HOME` for older tools)
explicitly whenever the AVD location matters.

### The Android emulator needs hardware virtualization, and a VM may not have it
`emulator -accel-check` is authoritative:

```
accel: 3
KVM requires a CPU that supports vmx or svm
```

If `/proc/cpuinfo` shows `hypervisor` but neither `vmx` nor `svm`, nested
virtualization is off **at the host** and nothing inside the guest — root
included — can enable it. The emulator still runs, in software (TCG). Measured
on such a host (Pixel 6, API 35): **805 s to boot, ~14 s per `screencap`**,
~1.4 s per input event, at ~1.0 load average because TCG is single-threaded per
vCPU. Input is usable; screenshot-based UI verification effectively is not.
Builds are unaffected — Gradle needs no KVM.

A fresh AVD also comes up on `com.android.settings.FallbackHome` rather than the
launcher, so `screencap` returns a blank image and looks broken. It is
unprovisioned:

```sh
adb shell settings put global device_provisioned 1
adb shell settings put secure user_setup_complete 1
```

Expect `system_server` to restart afterwards, which under TCG takes minutes and
reports `cmd: Can't find service: activity` throughout.

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

### `DEVELOPER_ERROR` on Play builds only, and the fingerprint matches

Sign-in works on every build you make and fails only for copies installed from
Play. You compare the app signing SHA-1 in Play Console against the one
registered, character by character; it matches. The OAuth client exists in Cloud
Console. Hours pass, so it is not propagation. Everything is correct and it still
fails.

**Play App Signing may be enrolled in "quantum-ready" hybrid signing, which is
not one certificate but three.** The App signing page then lists a **Classical
key** *and* a **Post-quantum cryptography key**, each with their own SHA-1 and
SHA-256, and any row under **Previous app signing keys** is a third certificate
still served to older devices. Google's guidance is that **all of them** must be
registered with API providers. Register one and the checks all pass while devices
handed either of the others fail — and the fingerprint anyone would think to
verify is the one that is already right.

So: read that page and register **every** SHA-1 it shows, not "the app signing
key". Then, before assuming a stale bundle is at fault:

**A rebuild cannot fix this, and it is worth knowing before you spend a version
bump on one.** The google-services plugin bakes only `default_web_client_id`,
`gcm_defaultSenderId`, `google_api_key`, `google_app_id`,
`google_crash_reporting_api_key`, `google_storage_bucket` and `project_id` into
the app — **no certificate hashes**. Confirm on any project:

```sh
cat android/app/build/generated/res/processReleaseGoogleServices/values/values.xml
```

Fingerprint registration is entirely server-side, so an artifact built before the
fingerprint was added starts working the moment it is registered. That matters
because on a store track a re-upload needs a NEW versionCode, so "just rebuild
it" is a version bump, a changelog entry and a re-review — spent on something
that was never the cause.

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

### The emulators "start", then die with a Java error

```
Emulator UI → http://127.0.0.1:4000
...
Error: Process `java -version` has exited with code 1.
Please make sure Java is installed and on your system PATH.
```

The banner is printed by your own script *before* firebase gets as far as the
Java check, so this reads like the emulators came up and then crashed. They never
started at all — Firestore and Auth are Java processes.

**On macOS, `command -v java` cannot tell you whether Java is installed.**
`/usr/bin/java` always exists, as a stub that exits 1 with "Unable to locate a
Java Runtime". So every `if command -v java` guard passes on a machine with no
JDK whatsoever. The only honest check runs it:

```bash
java -version >/dev/null 2>&1 || echo "no working JDK"
```

Two corollaries, both learned the expensive way:

- **Resolve the JDK in ONE file that every script sources.** Three scripts each
  carrying the same two-branch lookup (`$MY_JDK_HOME`, then `~/opt/jdk-21`) means
  a machine that has neither fails in three places with one cause and three
  different-looking symptoms. A `/usr/libexec/java_home -v 21` fallback, plus the
  Homebrew and Android-Studio-bundled JDKs, covers most developer Macs.
- **Fail with the list of places you looked.** "No working JDK 21 found; checked
  A, B, C" is repairable in seconds. Firebase's version of the message arrives
  later, from a different program, and names none of your configuration.

### Wiping the emulators does NOT sign the app out

You reset the emulators, re-seed, relaunch the app — and it sits on a "wrong
account" or "not provisioned" screen with nothing but a Sign out button. It reads
as the domain check or the approval gate being broken.

It is neither. **Auth persistence lives on the CLIENT and outlives the backend.**
On React Native the JS SDK persists the session to AsyncStorage — configured
deliberately, because without it every app restart signs the user out — so after
a wipe the app still holds a token for a uid the fresh Auth emulator has never
heard of. The account exists to the client and not to the server, and every
"auth account with no user doc" branch correctly reads that as a rejected
sign-in.

**The first run always works, which is what makes it confusing**: a seed that
mints new uids guarantees the mismatch from the SECOND run onward.

Clear the app's storage whenever you wipe the backend, so client and server are
the same age:

```bash
# iOS simulator — the DATA container, not the bundle
xcrun simctl terminate <sim> <bundle-id>
D=$(xcrun simctl get_app_container <sim> <bundle-id> data)
rm -rf "${D:?}/Documents" "${D:?}/Library"     # :? so an empty D cannot rm -rf /Documents

# Android emulator
adb shell pm clear <package>
```

Any script that resets emulators should do this in the same breath, rather than
leaving it to be rediscovered at the next confusing screen.

### Writes succeed, triggers log success, client says the doc does not exist
The listener even reports a *server* snapshot (`fromCache=false`).

The Firestore emulator **partitions data by project id**. A client configured
with a different id talks to a different database inside the same emulator.

Use one exported constant for the emulator project id on both client and server,
and pass the same value to `firebase emulators:exec --project`.

### A seeded account is permanently "not provisioned", and re-seeding cannot fix it
The seed script times out waiting for the first signed-in screen; the app sits on
whatever you show for "signed in but no profile" — a wrong-domain or rejected
message. The emulators are up, the ports answer, nothing errors.

**Firestore is ready seconds before the functions emulator finishes loading.** A
start-up script that waits on the Firestore port and then seeds races the
auth-create trigger. A sign-in landing inside that window creates an **auth
account with no user document** — and an app that infers "account exists, profile
does not ⇒ the server rejected this address" will show that forever.

Re-running the seed does not help: `onCreate` fires **once per account**, and the
account already exists. The state is only clearable by deleting the auth user
(`DELETE /emulator/v1/projects/<id>/accounts`).

Wait for the **trigger to be registered**, not for a port to answer. The emulator
log line is the only honest signal:

```bash
# ✔  functions[us-central1-onUserCreate]: auth function initialized.
until grep -q 'onUserCreate.*auth function initialized' "$LOG"; do sleep 3; done
```

The general shape: **port open ≠ trigger registered**, and a readiness check on
the wrong process fails by stranding data rather than by erroring.

### Admin-SDK `createUser({ password })` is indistinguishable from a client sign-up
An auth-create trigger usually has to tell populations apart, and the only thing
it can read is the new user's `providerData`. That list is emptier than you
expect, and the difference is decided by one argument:

| created as | `providerData` at trigger time |
|---|---|
| `createUser({ email })` — no password | **empty** |
| `createUser({ email, password })` | `['password']` |
| federated sign-in | `['google.com']`, etc. |

An empty list is therefore the Admin-SDK signature, and `['password']` is what a
**client-side sign-up** looks like — which is precisely the thing such a trigger
is usually written to reject, because no legitimate flow performs one. So a
seed or test fixture that helpfully passes a password to `createUser` is
classified as a self-signup and deleted, seconds after it was made.

The failure is nasty to read. It is asynchronous, so accounts appear to exist and
then do not; it looks intermittent, because it depends on trigger timing; and the
trigger is doing exactly what it was designed to do, so nothing errors. Create
without a password, then set one:

```js
const u = await auth.createUser({ email, displayName });   // no password
await auth.updateUser(u.uid, { password, emailVerified: true });
```

`onCreate` does not fire again, so the second call is invisible to the trigger.
This is also why the production path — invite the user, let them set their own
password from an emailed link — is the shape that works: it is password-less at
creation for a product reason, and the trigger's classification quietly depends
on it. Anything reproducing that flow in a script has to reproduce that detail
too.

Note an empty provider list is also what an **anonymous** sign-in has. An email
address is what separates the two.

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

**`OPTIONS` is load-bearing, not tidiness.** It is a CORS preflight, so the
emulator answers from its routing table without running the function body. Swap
it for a `GET` — the obvious simplification, and easy to do from memory — and the
probe now *invokes* whatever function you named, in a loop, before your suite has
started. If the only unauthenticated function you have is a bootstrap or a seed
(they usually are, since everything else demands auth), the readiness check has
just mutated the world it was about to test. A readiness check with a side effect
on the system under test is not a readiness check.

Safer still where it will do: probe services that have no function bodies at all
— the Auth emulator's `/emulator/v1/projects/<id>/config` and a plain `GET` on
the Firestore emulator root both answer 200 when up, and cannot do anything.

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

### A client timestamp your cleanup keys on must be bounded server-side
Rules that accept `createdAt is number` are fine while the field is decoration.
The moment a scheduled sweep decides what to delete BY AGE, that field is a
control input: a document claiming to be from the year 3000 is never older than
the cutoff, so it and its bytes live forever. Bound it against `request.time`.
Bound only the UPPER side, and generously — a tight bound refuses a real person
whose device clock is merely wrong, trading a rare cost leak for a broken
feature.

And decide deliberately what the sweep does with a record it CANNOT age (missing
or malformed timestamp). Skipping looks safe and is the wrong answer: the record
is stuck in its half-finished state, so skipping keeps it forever.

### Cache a downloaded file under its ID, never its display name
Two attachments on one record can share a display name — auto-generated names
stamped to the minute collide constantly. Key the on-disk cache by name and the
second download overwrites the first, so opening the first shows the SECOND
file's contents under the first one's name. Key it by id and keep the extension.

### A progress bar can render perfectly and show nothing
Check the CONTRAST of the fill against its track, not just that both are theme
tokens. A soft-accent fill on an inset track measured 1.13:1 — invisible — so
the only feedback during an upload displayed nothing while the upload worked.
Non-text UI wants ≥3:1 (WCAG 1.4.11). If the label sits on the bar, it cannot be
legible on both the filled and unfilled halves at once, so move the label off
the bar and let the fill be a real colour.

### Your source AndroidManifest is not the permission list
Libraries merge their own `uses-permission` entries in. A comment in your
manifest saying "only INTERNET and VIBRATE" is describing one input to the
merger, not the result — and it invites exactly the wrong conclusion at review
time. Read `android/app/build/intermediates/merged_manifest/…`, or the built
APK's badging, and say in the comment that the file is not the whole story.

### Waiting for a nav label is not waiting for the screen
`await page.getByText('People').waitFor()` then acting on the list is a trap when
"People" is ALSO the nav item or the menu entry that got you there: it is already
on screen, so the wait returns instantly and the next line samples a list that
has not loaded. In a test it looks like a flake; in a SEED script it is worse —
the loop finds nothing, exits, and the script reports success having done
nothing. One seed here silently produced a one-person board for weeks, so every
manual screenshot and every hand-test ran against an unrepresentative state.
Wait for the thing you are about to act on (the row, the Approve button), never
for the label of the screen it sits on.

**`isVisible()` is a sample, not a wait.** It answers about this instant and
returns false for anything a live query has not delivered yet, so a check
written as `if (!(await x.isVisible())) skip()` silently skips. One role audit
reported "not a member" for an ADMIN that way — the board was simply two seconds
behind the nav bar. If the answer decides what the test concludes, use
`waitFor()` and treat the timeout as the negative result.

### Sanitise client-side too, or the row renames itself
If the server normalises a user-supplied name and the client does not, the value
visibly CHANGES the moment the server writes it back — the file you attached as
`report".pdf` becomes `report_.pdf` under your cursor. Worse, if security rules
bound the field, an ordinary long name fails with a raw `permission-denied`
instead of a sentence. Run the same shared sanitiser on both sides: the server
because it is the boundary, the client so the result is never a surprise.

### Truncating a filename by slicing the front cuts the extension off
`name.slice(0, MAX)` on a long filename drops `.pdf`, and the extension is what
your UI shows as the file's kind and what some viewers sniff to pick a handler.
Shorten the STEM and keep the suffix.

### A MIME type from a client is a response header — match the grammar
A `contentType` you store on an object comes back as `Content-Type` on a
response. Checking "does it contain a slash" lets `application/pdf\r\nX: 1`
through unchanged, which is a header-injection shape. Match RFC 6838's token
grammar (`type/subtype`, restricted characters, bounded length) and discard
anything that does not fit rather than trying to repair it.

### `firebase emulators:exec` can hang AFTER the tests pass
Symptom: the suite prints its passes, the emulators log "Shutting down", and
then nothing. The process never exits, so whatever runs it — a battery script,
CI, an agent — waits forever on a run that actually succeeded. Seen holding a
session for three hours.

Two consequences worth designing around:

- **Wrap it in a timeout.** `timeout 900 npm run test:emulator` turns a hang
  into a reported result instead of a stalled pipeline.
- **Do not read pass/fail from the wrapper's exit code.** A teardown hang killed
  by a timeout exits 124 while every test passed; treating that as failure sends
  you hunting a bug that is not there. Grep the runner's own counts out of the
  log and report the exit code separately.

Leftover emulator processes are the related trap: they hold the emulator ports
and the next run dies with "port taken". Kill by matching the process's **cwd**
to the repo, not by name alone — sibling projects on the same machine run the
same binaries, and `firebase-tools` does not match the launcher process, which is
`bin/firebase`.

**The worse leftovers hold no port at all.** When a run is killed, the functions
emulator's Node **runtime workers** can survive it, reparent to init, and sit
there at ~150 MB each. They are invisible to every port check — `ss` says the
block is clear, the next run starts happily — and they accumulate one batch per
aborted run. Measured after three interrupted runs: twelve orphans, ~1.7 GB, all
`ppid=1`.

That produces a genuinely confusing failure loop, because the cost lands on the
*next* run rather than the one that leaked: a long browser suite dies partway
with `ERR_CONNECTION_REFUSED` against its own dev server, at a *different* screen
each time, and the dev server's log ends with no error at all — the signature of
a process that was killed rather than one that crashed. It reads as flakiness in
whatever you changed most recently. Clearing the orphans makes the same suite
pass unchanged.

So when a suite fails that way, count the orphans before suspecting your diff:

```sh
ps -eo pid,ppid,rss,args --no-headers | grep "[f]irebase-tools" |
  awk '$2==1 {n++; kb+=$3} END {printf "%d orphans, %d MB\n", n, kb/1024}'
```

and identify each one's owner with `readlink /proc/<pid>/cwd` before killing it,
since on a shared machine some of them will belong to another checkout.

### The functions emulator SERIALISES calls to a warm instance — so races vanish
Fire N concurrent requests at a callable through the emulator and they may run
one after another, because a warm instance handles them in turn. A race test
driven over HTTP therefore **passes against genuinely broken code**. The cruel
part is that it can reproduce once, on a cold start, and then never again — so
you "confirm" the bug, fix it, and keep a test that has stopped testing.

Test the race IN-PROCESS instead: extract the effect from the callable (the
callable becomes auth + validate + delegate) and drive the extracted function
with `Promise.all`. Two promises in one process genuinely interleave on Firestore
round-trips. The same split is worth having anyway — it is the only way to test
a scheduled function's body without a pubsub emulator.

### Read-then-write in a callable is a race, and Firestore will not save you
`const snap = await ref.get(); if (snap.exists) { await ref.delete(); log(); }`
is two round-trips with a window between them. Two taps on a slow connection, or
two people on the same card, both see the document and both log. Same for "if
status is pending, set it to done and record it". Put the state transition in
`runTransaction` and let **only the caller whose transaction actually made the
change** write the follow-on effect. Cheap, and the alternative is duplicate
history entries nobody can explain later.

### Attribute an action to the actor in the DATA, not the caller
A confirm/finalize step is often invoked by whoever happens to be there — a
retry, another device, a different person on the same board. If it writes "X did
this" from `request.auth.uid`, the record is wrong exactly when it matters. Take
the actor from the document (`uploadedBy`, `createdBy`) whenever the document
knows better than the caller does.

### Storage rules cannot read your database, and everything follows from that
Cloud Storage security rules have no `get()` into Firestore. If who-may-see-this
lives in a document — a membership array, an org id, a team — **the rule cannot
ask**. It can only reach the auth token.

The workable shape is: the DATABASE record is the upload's authorization. A
rules-checked write creates it, and the object goes to a path derived from ids
only that write could have produced. The Storage rule then only has to say "an
active account, write-once, under this size". Reads stay denied outright and
every download is a short-lived signed URL from a callable that re-checks
membership. Accept, and write down, the residual: someone who knows an id can
push bytes to a path they should not. They are unreadable, but they are billable.

### `allow write` in Storage rules includes DELETE — so write-once blocks cleanup
`allow write: if resource == null` is the standard write-once rule, and it also
silently means **the client can never delete the object**, because `resource` is
non-null on a delete. Any "on failure, undo what I just uploaded" path in the
client therefore deletes only the database record and leaves the bytes:
unreferenced, unreadable, invisible, and billed forever. Undo has to be a
server-side callable. And a retry must mint a NEW id — a second write to the same
path is refused, which surfaces as an alarming permission error on an ordinary
retry.

### Decide inline-vs-download on the OBJECT, not on the signed URL
`getSignedUrl` accepts `responseDisposition`/`responseType`, and they work — in
production only. The emulator serves objects through its own `?alt=media`
endpoint, which honours the object's STORED `contentType`/`contentDisposition`
and ignores query overrides. So the whole question of whether a PDF renders or
downloads, and whether the filename survives, is exercised by no local test.
Write both onto the object when you finalize the upload instead; then the
emulator and production serve identical headers and the behaviour is assertable.

Two things to get right while you are there. Non-ASCII filenames need RFC 6266
`filename*=UTF-8''<pct-encoded>` with an ASCII `filename="…"` fallback; a bare
quoted form cannot carry them. And **never serve attacker-supplied `text/html` or
`image/svg+xml` inline** — it executes script on the storage host's origin.
Normalise those to `application/octet-stream`.

### The emulator mints URLs against ITS OWN host, which is not the device's
A functions emulator building an object URL uses `127.0.0.1`. On an Android
emulator that address is the DEVICE, so the download fails with `Failed to
connect to /127.0.0.1:9199` — which reads as a broken feature and is pure
addressing. Rewrite the host client-side, **gated on emulator mode**: a real
signed URL covers its host in the signature, so rewriting one breaks it.

### `clearStorage()` is not synchronous, and it corrupts the NEXT test
`testEnv.clearStorage()` in a `beforeEach` returns before the emulator has
finished deleting. The deletion can land in the MIDDLE of the following test and
remove an object that test just uploaded. The signature is vicious: a write-once
assertion sees the second upload succeed, so the test fails pointing straight at
your rule — and passes in isolation, so only the full suite shows it. Give every
storage test its own object path instead of relying on the clear.

### Opening a file in the system viewer is three steps on Android, one on web
A browser takes a URL. Android will not: a viewer refuses a remote URL, and it
cannot read a `file://` path out of your sandbox. Download to your own cache,
convert with `FileSystem.getContentUriAsync` (Android-only, and only in
`expo-file-system/legacy`), then `IntentLauncher.startActivityAsync('android.intent.action.VIEW',
{ data: contentUri, flags: 1 })` — `flags: 1` is FLAG_GRANT_READ_URI_PERMISSION
and without it the viewer is handed a path it may not read.

You must also declare `<queries><intent><action android:name="android.intent.action.VIEW"/>
<data android:mimeType="*/*"/></intent></queries>`. On API 30+ package visibility
hides every handler otherwise, and the failure is silent — the tap does nothing
at all. `expo-intent-launcher` ships an empty manifest, so this cannot come from
the library. Fall back to the share sheet when nothing claims the type.

### `shareAsync` has ONE slot, and a duplicate tap is rejected outright
`expo-sharing` stores a single `pendingPromise`: set before the chooser starts,
cleared only when the activity result comes back. A second `shareAsync` while one
is outstanding throws `ERR_SHARING_IN_PROGRESS`, and the raw rejection reads
*"Call to function 'ExpoSharing.shareAsync' has been rejected. → Caused by:
Another share request is being processed now."* — a sentence about function calls,
shown to someone who tapped a PDF twice.

Match the **code**, not the message: expo infers `ERR_SHARING_IN_PROGRESS` from the
exception class name, so it survives a rewording upstream.

The real defect is upstream of the mutex. Opening is slow — mint a signed URL,
then download the whole file — and if the row does not change while that happens,
tapping again is the reasonable thing to do. Show the work on the row that was
tapped and stop accepting taps on it.

### A `busy` flag is state, so it cannot stop a same-frame double tap
`const [busy, setBusy] = useState(false)` plus `disabled={busy}` is the usual
guard, and it is a frame late: two taps inside one frame both read the value from
before the first, and the DOM still carries the old handler because React has not
re-rendered. It covers a slow double tap and nothing faster.

Where a duplicate is genuinely harmful — a native single-slot API, a payment, a
non-idempotent write — gate on a **ref**, read and written synchronously in the
handler, and keep the state purely for rendering. Write both through one
begin/end pair so they cannot drift.

```tsx
const busyRef = useRef<string | null>(null);
const begin = (id: string) => {
  if (busyRef.current !== null) return false;   // synchronous, no render needed
  busyRef.current = id;
  setActive(id);                                 // for the UI only
  return true;
};
```

Check the flag reaches the control, too. A panel where every other button took
`disabled={busy}` had exactly one action that did not, and that was the one that
broke.

### On web, open the tab BEFORE you have the URL
Minting a signed URL is async. `await getUrl(); window.open(url)` is a
popup-blocker false negative: the browser sees a programmatic open with no
gesture behind it, blocks it silently, and nothing happens and nothing throws.
Open a blank tab synchronously in the click handler, then set its location when
the URL arrives. Do not pass `noopener` in the feature string — it makes
`window.open` return null, which is the handle you need; sever `tab.opener`
manually instead.

### A picker's `fileName` can be present and useless
An Android gallery reports a MediaStore id (`1000000089.png`) and the camera a
bare UUID. A "keep the name if there is one" fallback never fires, and a card
with three photos lists three identifiers nobody can tell apart. Treat a
purely-numeric or UUID-shaped basename as absent and generate something readable
with a timestamp.

### Library manifests merge permissions you did not ask for
`expo-file-system` and `expo-image-picker` both declare READ/WRITE_EXTERNAL_STORAGE
(capped at API 32) in their own manifests, and the merger folds them into your
app silently. Check the MERGED manifest
(`android/app/build/intermediates/merged_manifest/...`), not your source one.
Suppress with `tools:node="remove"` only where you are sure — a permission a
library declares for a path your test devices are too new to exercise is one you
cannot verify removing, and stripping it breaks the feature for whoever has the
oldest phone.

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

### The app icon you configured is not the icon on the launcher

You set `icon` and `android.adaptiveIcon` in `app.json`, drop the PNGs in
`assets/`, rebuild, and the launcher still shows the old icon — or Expo's default
scaffold one. Nothing warns you; the build succeeds.

Same root cause as the config-plugin entry above: **Gradle compiles
`android/app/src/main/res`, and `app.json` is not consulted at build time.** With
a committed `android/`, `expo run:android` and `assembleRelease` never re-run
prebuild, so the mipmaps are whatever was committed. The config keys are inputs
to a *generator you are no longer running*.

`expo prebuild` would regenerate them — and take the rest of the native project
with it. **Prebuild defaults to CLEAN**: it deletes the native folder and
recreates it from the template, and `--no-clean` is the opt-out, not the other
way round. Hand edits go with it; a hardcoded `minSdkVersion` is the usual
casualty, and you find out when the floor you set for a permission-free API has
quietly dropped back to Expo's default.

It clears only the platforms named by `--platform`, so **scoping is what makes it
safe** — `--platform ios` will not touch a committed `android/`. A bare
`npx expo prebuild` hits every configured platform. There is a backstop (it bails
on a dirty git tree when it would delete an existing native folder), but a clean
tree is exactly when you are most likely to run it.

This asymmetry is worth designing for deliberately: commit the platform that has
hand edits, gitignore the one that does not, and keep everything the derivable
one needs in `app.json` — because **nothing changed in Xcode's UI survives a
regeneration**.

So write the resources yourself, matching exactly what prebuild would emit
(`@expo/prebuild-config/build/plugins/icons/withAndroidIcons.js` is the
authority — read it rather than guessing, it is a few hundred readable lines):

- `mipmap-<density>/ic_launcher_foreground.webp` at **108dp** × {1, 1.5, 2, 3, 4}
- `mipmap-<density>/ic_launcher.webp` and `ic_launcher_round.webp` at **48dp** ×
  the same scales (round is a circle crop)
- `mipmap-anydpi-v26/ic_launcher.xml` **and** `ic_launcher_round.xml`, both
  pointing at `@color/iconBackground` and `@mipmap/ic_launcher_foreground`
- `<color name="iconBackground">` in `values/colors.xml`

Keep `app.json` in sync anyway, so a future prebuild is a no-op rather than a
conflict.

**The safe area is 66.67%, not "about two thirds".** The foreground is resized to
fill the whole **108dp** layer, of which only the central **72dp** survives the
launcher's mask. On a 1024px canvas that is a safe **radius of 341** — eyeballing
it at 350 puts 9px of artwork where a circular mask shaves it, which reads as a
flat edge on one side of a disc. Prove it on pixels rather than arithmetic:
composite the foreground over the declared background colour, mask with a circle
inscribed in the inner 72/108, and assert no ink is lost.

Verify on a device, not from the build. The zip listing will not help — resource
shrinking renames everything to `res/-6.webp` — so install it and read the
launcher:

```bash
adb shell input keyevent KEYCODE_HOME && adb shell input swipe 540 2000 540 400 300
adb exec-out screencap -p > drawer.png     # then actually look at it
```

A web favicon has the mirror-image trap: `web.favicon` **does** still apply when
you override Expo's HTML template with your own `public/index.html` — the export
injects the `<link rel="icon">` into whatever template you supply. Confirm by
grepping the exported `index.html`, not by reasoning about it.

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

### The version number is a store contract, and Android hides that from you
Adopt this before the first release even if iOS is hypothetical. Fixing it later
costs a re-release, because by the time App Store Connect tells you, the version
is already tagged, built and installed on people's phones.

**The version is exactly three integers, `X.Y.Z`, in ONE file** (`app.json` →
`expo.version`). Everything else derives from it.

No pre-release suffix (`1.2.3-beta.1`), no fourth component, no leading `v`, at
most 18 characters, strictly increasing, never reused. These are Apple's, from
[TN2420](https://developer.apple.com/library/archive/technotes/tn2420/_index.html):
`CFBundleShortVersionString` takes digits and periods only, at most three
components. Android is far laxer about the version *name* — which is the trap. A
scheme that worked for years on Android is rejected the first time it meets App
Store Connect, and nothing warns you in between. Starting at `0.x` is fine:
`0.25.0 < 1.0.0`, so the eventual jump still increases.

**Also ban leading zeros**, which the shape check `^\d+\.\d+\.\d+$` lets through.
`2026.07.01` is legal to Apple, but `07` and `7` are the same number, so a
date-style scheme can produce a version that does not increase. Use
`^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$`.

**The Android `versionCode` bites first.** Derive it from the semver, and give
each field *three* digits. The common two-digit scheme collides:

```
0.1.99 -> 199,  0.1.100 -> 200,  0.2.0 -> 200   <-- same number
versionCode = major*1000000 + minor*1000 + patch      // 0.25.0 -> 25000
```

That leaves room for 999 minor and 999 patch, and major up to 2147 before
Android's signed-32-bit ceiling. **Throw from the build** on a version that is
malformed or out of those ranges, rather than silently computing a wrong number —
a collision is invisible until an install refuses.

Android refuses to install an APK whose `versionCode` is not greater than the
installed one, so that release simply never goes out. Widening the multipliers
later is safe; narrowing never is — check the new formula produces a larger
number than the old one did for the current version.

Enforce it in **three** places, because each catches what the others cannot: a
CI/lint script (catches a web-only release that never runs Gradle), the Gradle
config (fails even when nobody ran the script), and the release step (the last
gate before a tag and a public download exist). And **test the validator against
the shapes it exists to stop** — `1.2.3-beta.1`, `1.2.3.4`, `v1.2.3`,
`2026.07.01`, `0.1.1000`. A self-test that runs on every invocation costs
microseconds; writing one is how you discover your regex accepts dates.

When iOS actually arrives, `CFBundleVersion` (the build number) is **separate**
and needs its own scheme — on iOS it must increase within a version train and may
repeat across trains; on macOS it must increase forever and may never repeat. Do
not assume it can mirror `versionCode`. Git tags may keep a `v` prefix; Apple
never sees your tags, only the bundle.

### `pod install`: a Swift pod "cannot yet be integrated as a static library"

```
[!] The following Swift pods cannot yet be integrated as static libraries:
The Swift pod `AppCheckCore` depends upon `GoogleUtilities` and
`RecaptchaInterop`, which do not define modules.
```

Expo's autolinker already fixes this class of error for you — but only **one
level deep**. `autolinking_manager.rb` calls `use_modular_headers_for_dependencies`
on the direct dependencies of each Expo module's podspec, so a Swift pod two
levels down is never reached:

```
ExpoAdapterGoogleSignIn        <- an Expo module, so Expo processes it
  └─ GoogleSignIn              <- gets modular headers
      └─ AppCheckCore          <- Swift pod, NOT covered
          ├─ GoogleUtilities       <- ships no module map, never gets one
          └─ RecaptchaInterop      <- same
```

Fix it with `expo-build-properties`, naming only the pods that actually lack the
maps. This is the remedy CocoaPods itself prints, and it survives prebuild
because it lives in `app.json` rather than in the generated `Podfile`:

```json
["expo-build-properties", {
  "ios": { "extraPods": [
    { "name": "GoogleUtilities",  "modular_headers": true },
    { "name": "RecaptchaInterop", "modular_headers": true }
  ]}
}]
```

**Do not reach for `ios.useFrameworks: "static"` first**, even though it is the
answer most search results give. It relinks *every* pod in the project, and
Expo's own docs warn that React Native's precompiled xcframeworks can fail under
it — `forceStaticLinking` exists purely to mop that up. There are also plenty of
reports of it not fixing this error at all. Scope the fix to the pods that need
it.

### The archive SUCCEEDS and contains no app

`xcodebuild archive` prints `** ARCHIVE SUCCEEDED **`, then the export fails with
something that names nothing useful:

```
error: exportArchive exportOptionsPlist error for key "method":
       expected one {} but found app-store-connect
```

The empty set `{}` is the tell: **there are no valid export methods, because the
archive holds no app.** You archived a *pod*.

Discovering the scheme from the **workspace** is what does it. Before pods
integrate there is barely a workspace at all; afterwards it carries a scheme for
every pod — well over a hundred — so anything taking `schemes[0]` gets whichever
sorts first alphabetically (`AppAuth`, in any Google-Sign-In app). Archiving a
static library succeeds perfectly and quietly.

Ask the **app project** instead, which knows exactly one scheme:

```bash
PROJECT="$(find ios -maxdepth 1 -name '*.xcodeproj' | head -1)"  # Pods.xcodeproj is deeper
xcodebuild -project "$PROJECT" -list -json                       # .project.schemes, NOT .workspace.schemes
```

Then assert the result, because this failure is silent by construction:

```bash
[ -d "$ARCHIVE/Products/Applications" ] || die "archive contains no app — wrong scheme"
```

### `-allowProvisioningUpdates` fails with "Cloud signing permission error"

```
error: exportArchive Cloud signing permission error
error: exportArchive No signing certificate "iOS Distribution" found
error: exportArchive No profiles for '<bundle id>' were found
```

The archive is fine. **The App Store Connect API key lacks the role needed to
create a distribution certificate.** Certificates, Identifiers & Profiles is
reachable over the API only by an **Admin** key — App Manager and Developer
cannot touch it, however well they upload builds.

The tell is on the build machine, and it reads like "signing is broken" when it
is really "this key may only sign for debugging":

```bash
security find-identity -v -p codesigning
#   "Apple Development: Created via API (KEYID)"   <- the key works...
#   (no Apple Distribution entry at all)           <- ...but only for development
```

A key that has created *development* certificates and no distribution one is a
role problem, not a broken key or a bad `.p8`. Give it Admin in App Store Connect
→ Users and Access → Integrations; if the role cannot be edited after creation,
generate a new Admin key. Only the key id changes — nothing in the repo does.

Two things that save a rebuild here:

- **Prove the fix in seconds**, not in another twenty-minute archive: re-export
  the archive you already have with `destination: export` in the options plist.
  It exercises exactly the step that failed and uploads nothing.
- **A cloud-managed distribution certificate does not persist in the keychain.**
  After a successful export, `security find-identity` still shows no distribution
  identity. That is expected — it is fetched for the export and discarded — so do
  not read its absence as failure.

### `errSecInternalComponent` twenty minutes in: the Mac is headless

The archive gets past prebuild, `pod install` and every compiled target, then
dies at the **first framework it signs**:

```
Code Signing …/YourApp.app/Frameworks/SomeFramework.framework
  with Identity Apple Development: Created via API (…)
…/SomeFramework.framework: errSecInternalComponent
Command PhaseScriptExecution failed with a nonzero exit code
** ARCHIVE FAILED **
```

Nothing there names a keychain, and the entry above trained you to read a
signing message as a provisioning problem. It is neither. **The login keychain
unlocks at GUI login, and an ssh session never has one**, so `codesign` can read
the certificate — public data — while the private key is out of reach.

Two commands separate this from every other signing failure:

```console
$ launchctl managername
Background                                    # `Aqua` = GUI session; this is not one

$ security show-keychain-info ~/Library/Keychains/login.keychain-db
security: SecKeychainCopySettings …: User interaction is not allowed.
```

`security find-identity -v -p codesigning` lists **valid identities the whole
time**, which is exactly why this reads as a configuration problem. Unlock it,
typed at the prompt rather than passed with `-p`, which would put an account
password into shell history:

```bash
security unlock-keychain ~/Library/Keychains/login.keychain-db
```

The unlock is shared by every process of that user, so another terminal will do,
and it is **runtime state**: it dies with a reboot, and a build box nobody logs
into at the console starts locked every single time.

**Gate it, because signing anything proves it in about a second** — a throwaway
binary exercises the same mechanism as a framework, and turns a twenty-minute
failure into an instant one:

```bash
SIGN_ID="$(security find-identity -v -p codesigning | awk '/^ *1\)/ {print $2}')"
[ -z "$SIGN_ID" ] || {                        # absent is fine: cloud signing mints one
  cp /bin/echo "$TMP/probe"
  codesign --force --sign "$SIGN_ID" "$TMP/probe" || die "keychain locked or key ACL refuses"
}
```

If the keychain is open and signing still fails, it is the private key's ACL
refusing a session with no window server, which an unlock does not address:
`security set-key-partition-list -S apple-tool:,apple:,codesign: -s <keychain>`.

### The App Store Connect key is not only an upload credential

It is natural to gate the key behind the flag that decides whether to upload,
because that is what its name suggests it is for:

```bash
if [ "$UPLOAD" = true ]; then          # WRONG
  : "${ASC_KEY_PATH:=$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
fi
xcodebuild ... -allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" ... archive
```

**`-allowProvisioningUpdates` mints and downloads the signing assets THROUGH that
key**, so the *archive* needs it exactly as much as the upload does. Without it
the archive falls back to whatever is already in the keychain — which, on a
machine where the distribution certificate is cloud-managed, is nothing.

Resolve the key for every build; gate only the genuinely upload-specific checks:

```bash
if [ -n "${ASC_KEY_ID:-}" ]; then      # every build
  : "${ASC_KEY_PATH:=$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
fi
if [ "$UPLOAD" = true ]; then          # only the upload needs the issuer id
  [ -n "${ASC_ISSUER_ID:-}" ] || die "..."
fi
```

The reason this survives review: the *uploading* path is the one everybody runs,
and it works. A `--no-upload` or `--dry-run` route can be broken from the day it
was written and nothing notices, because the only person who would run it is
someone deliberately trying not to ship.

### An empty bash array under `set -u` is "unbound" on every Mac

macOS ships **bash 3.2** — frozen at the last GPLv2 release, and still what
`#!/usr/bin/env bash` finds unless someone installed another. In 3.2, expanding
an *empty* array counts as unbound:

```bash
set -euo pipefail
AUTH=()
xcodebuild ... "${AUTH[@]}"     # -> AUTH[@]: unbound variable, and the script dies
```

The message names a variable that is right there, declared, four lines up — so it
reads as a typo or a scoping bug rather than what it is. Bash 4.4 and later
expand it to nothing, as intended, which means **it cannot be reproduced in any
shell newer than the one every Mac actually runs**, including whatever your CI
image has.

Use the `+` form, which expands to nothing when the array is empty:

```bash
xcodebuild ... ${AUTH[@]+"${AUTH[@]}"}
```

Two multipliers worth knowing. `shellcheck` does not flag it — the code is valid,
it is the runtime that differs. And it only fires on the branch where the array
is genuinely empty, so the usual shape is a script that has worked for months
failing the first time someone takes the unusual path.

To prove a fix here, run the two forms rather than reasoning about them:

```bash
bash -c 'set -u; A=(); printf "%s" "${A[@]}"'          # bash: A[@]: unbound variable
bash -c 'set -u; A=(); printf "%s" ${A[@]+"${A[@]}"}'  # (nothing, exit 0)
```

### `expo run:ios` exits 1 on a build that actually worked

The app compiles, signs and installs on the simulator — and the command still
fails, with a stack that names nothing you did:

```
at isSimulatorAppRunningAsync (.../ios/ensureSimulatorAppRunning.js)
at osascriptSpawnAsync (.../@expo/osascript/build/index.js)
```

Its **last** act is raising the Simulator window through AppleScript, which is
not permitted from a non-GUI shell — CI, an agent, an ssh session. Everything
that matters already happened before it.

**Never gate on that exit code.** Verify the install, and launch through
`simctl`, which needs no automation permission:

```bash
npx expo run:ios --device "iPhone 17 Pro" || true
xcrun simctl get_app_container "iPhone 17 Pro" com.example.app >/dev/null 2>&1 || exit 1
xcrun simctl launch "iPhone 17 Pro" com.example.app
```

This is the same shape as the archive that succeeds on the wrong target: the
exit code describes the tool's last step, not your goal. Assert the artefact.

### One failed UI-test flow wedges every later `simctl` for ten minutes

A UI flow fails. From then on **everything** simulator-related hangs — the
screenshot of that very failure, the reset after it, the next whole run — and
each hang looks like its own separate problem. `xcrun simctl list` simply never
returns.

The cause is a single process, worth knowing by name:

```
simctl diagnose -l -b --timeout=600 ... /Logs/Test/….xcresult/…/Diagnostics
```

On failure the XCUITest runner driving the simulator (Maestro's, and it will not
be alone) collects simulator diagnostics, and that dump **holds CoreSimulator for
up to 600 seconds**. Nothing announces it; you observe a machine that has
apparently gone bad, and "the simulator is flaky" becomes the diagnosis instead
of one lock with a name.

Reap it in the failure path, BEFORE gathering any evidence of your own:

```bash
pkill -9 -f "simctl diagnose"; pkill -9 -f maestro-driver-ios
pkill -9 -f com.apple.CoreSimulator.CoreSimulatorService   # only if still stuck
```

**The general lesson outlives the tool: a failure handler blocked by the
failure's own cleanup.** The screenshot-on-failure was defeated by the thing that
ran *because* of the failure. Any harness gathering evidence after something goes
wrong deserves that check, on any platform.

And bound every `simctl` call — an unbounded `execFileSync` turns a ten-minute
lock into a suite that never returns, which is strictly worse than one that
fails.

### Driving a simulator's UI: `simctl` has no tap

`xcrun simctl` boots, installs, launches, screenshots and `openurl`s — but it
cannot **tap, swipe or type**. Scripting a UI flow needs a driver. Prefer a
maintained one: **idb's last release is 2022** and its companion degrades mid-run
against modern iOS — a tap returns exit 0 and does nothing, which is the worst
failure mode a harness can have. Two things about idb cost an afternoon before
that became clear:

- **`idb_companion` must be launched by its real path, never a symlink.** It
  resolves its sibling `Frameworks/` through `@rpath`, which a symlink on `PATH`
  breaks. Use a wrapper script that `exec`s the real binary.
- **`IDB_COMPANION` is a socket address, not a path to the binary.** Pointing it
  at the executable fails with `Socket operation on non-socket`. Run
  `idb_companion --udid <UDID>`, read the `grpc_port` it prints, then
  `idb connect localhost <port>`.

Coordinates are in **points, not pixels** — divide screenshot pixels by the
device scale factor (3 on a modern iPhone) or every tap lands off-screen.

Best of all, `idb ui describe-all` returns the accessibility tree with
`AXLabel`s. Assert against those rather than coordinates: it is stable across
device sizes, and it is the only automated way to check that **icon-only
controls actually carry the labels they are supposed to** — something a
screenshot test can never see.

## Native touch

### A button in a dialog does nothing, then works on the third tap
Reported as slowness — "there's no immediate response, sometimes several
seconds" — because from the outside a tap that is discarded and a tap that is
slow look identical. It is neither: the taps are being eaten.

The shape is a scrolling container with a text field in it and the button that
acts on that field. A sheet, a picker with a filter above the rows, an inline
composer inside a list. You tap the button, nothing happens, you tap again.

`ScrollView`'s default is `keyboardShouldPersistTaps="never"`, and React
Native's own source says what that does:

> the keyboard is up, `keyboardShouldPersistTaps` is `'never'` (the default),
> and a new touch starts with a non-textinput target (in which case **the first
> tap should be sent to the scroll view and dismiss the keyboard, then the
> second tap goes to the actual interior view**)

The scroll view returns `true` from `onStartShouldSetResponderCapture`, so it
takes the responder in the **capture** phase and the `Pressable` under the
finger never becomes responder. `onPress` never runs — and, the tell that
separates this from every "my handler is slow" theory, **the control never
shows its pressed state either**.

**Under edge-to-edge on Android it does not stop at one tap.** The guard is "a
`TextInput` is focused AND a soft keyboard may be open", and the second half is
`_keyboardMetrics != null`, cleared by `keyboardDidHide` — an event RN does not
reliably deliver when the IME is tracked through WindowInsets. The keyboard goes
away, the field keeps focus (the caret is still blinking in it), and the scroll
view goes on eating taps with nothing on screen to explain why.

Confirm it from a screen recording before changing anything, because "slow" and
"discarded" need different fixes and the user cannot tell them apart:

- Step through frames and find the touch indicator (enable *Show taps* in
  developer options). If it is inside the control's bounds, delivery is fine.
- Sample the control's **fill colour** across the tap. `Pressable` renders a
  pressed style; measure it rather than eyeballing it. A tap that leaves the
  fill at full strength never started a press, which is a different bug from a
  press whose handler took a second.
- Check whether a caret is still blinking in a field elsewhere on screen. That
  is the precondition, and it survives the keyboard being dismissed.

The fix is `keyboardShouldPersistTaps="handled"` on every scroller that
contains controls: a tap a child handles reaches it, a tap nothing handles still
dismisses the keyboard. `"always"` is right only for a scroller with nothing
tappable in it.

**Guard it with lint, not a test.** If your e2e is Playwright — and on this
stack it is, because the web surface is the one a browser can drive — no test
you can write will see this: it is native responder behaviour with no DOM
equivalent. A green suite says nothing at all here.

```js
// eslint.config.mjs — the bar is "say something", not "say handled";
// `always` is a legitimate answer, silence is not.
{
  selector:
    'JSXOpeningElement[name.name=/^(ScrollView|FlatList|SectionList)$/]' +
    ':not(:has(JSXAttribute[name.name="keyboardShouldPersistTaps"]))',
  message: 'Set keyboardShouldPersistTaps — the default eats the next tap.',
}
```

Two traps in placing that rule. `no-restricted-syntax` is one rule name, and
**flat config replaces a rule rather than merging it** — a second block setting
it over the same files silently disables the first, and `npm run lint` still
passes. Declare the selector sets as constants and spread every set that applies
into each block. Then prove the rule can fail: introduce one violation of *each*
set, see both errors, revert. A green run you have not falsified is not evidence
the rule is live.

## react-native-web

### A control ignores your theme colours
`Switch` ignores `thumbColor`/`trackColor`, and the RNW-specific
`activeThumbColor`/`activeTrackColor` are gone in 0.21 — it renders Material
teal. Build toggles from `Pressable` and views you control. Assume any RNW
control wrapping a platform widget may not be themeable, and confirm with a
screenshot rather than trusting the props.

### A raw DOM element inside your app renders in Times, at the wrong size
The moment you mount something react-native-web did not render — a
`contenteditable` from a rich-text library, a third-party web widget, anything
reached through a `.web.tsx` seam — its text comes out in the browser's default
serif at the browser's default size, sitting inside an app that is otherwise
sans.

RNW resolves `fontFamily: 'System'` to a font stack and writes it onto **each
`Text` element's own class**. It never sets it on `body`, and `View` does not set
it either, so there is nothing in the ancestor chain for a foreign element to
inherit. Font size is the same story: your app has a type scale, the UA has
`16px`, and a bare element gets the UA's. A `TextInput` on native is a third
answer again (RN defaults to 14), so the same editor can differ from the app in
one direction on web and the other on native.

Nothing catches this. Colour lint rules do not look inside CSS strings, the
element is styled correctly by every assertion you wrote, and the layout is not
broken — only the typeface is, and only in a region you probably screenshot
rarely because it is behind an "edit" affordance.

Set the font explicitly on the foreign element, from the same tokens the app
uses, and be careful about specificity: an **inline** `fontSize` beats the class
rule you added, so keep both in one place rather than half in each.

Then assert it by comparison, not by restating the stack:

```js
const f = await page.evaluate(() => {
  const norm = (v) => v.replace(/\s+/g, '').replace(/"/g, '').toLowerCase();
  const foreign = document.querySelector('[contenteditable="true"]');
  const native = /* any element RNW rendered, e.g. a button's text node */;
  return {
    a: norm(getComputedStyle(foreign).fontFamily),
    b: norm(getComputedStyle(native).fontFamily),
  };
});
// a === b, computed against a real rendered control — hardcoding the expected
// stack would just restate the assumption that produced the bug.
```

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

### A swipe pager puts EVERY page in the accessibility tree at once
A carousel/pager built on a horizontal `ScrollView` lays out all its pages —
that is how swiping works — so all of them are in the accessibility tree
simultaneously. Sighted users see one page; a screen reader walks every page's
content with nothing to say which page it is in, and any control the page
template repeats is announced once per page ("Add card", nine times).

It also breaks test selectors in a way that looks like a product bug: a
role-based lookup for a control that is visually unique resolves to N elements
and fails as a strict-mode violation.

Hide the off-screen pages, using all three spellings, because they are three
platforms' names for the same idea:

```jsx
<View
  aria-hidden={!onScreen}                                     // react-native-web
  accessibilityElementsHidden={!onScreen}                     // iOS
  importantForAccessibility={onScreen ? 'auto' : 'no-hide-descendants'}  // Android
>
```

**Verify against the accessibility TREE, not the DOM.** `querySelectorAll`
returns `aria-hidden` nodes happily, so a DOM-based audit reports identical
numbers before and after the fix and the fix looks ineffective. Playwright's
role engine skips `aria-hidden` subtrees — the same rule a screen reader
follows — so a role-locator count is the tree count. Assert BOTH, because
`tree === 1` alone also passes when the screen renders nothing:

```js
const tree = await page.getByRole('button', { name: 'Add card', exact: true }).count();
const dom  = await page.evaluate(() => document.querySelectorAll('[role="button"]').length);
// expect tree === 1 && dom > 1
```

(`page.accessibility.snapshot()` is removed in current Playwright — reach for
role locators instead.)

### Pager BUTTONS flip the header back and forth; swiping does not
Symptom: tapping a next/prev arrow makes the header name the new page, snap back
to the old one, then settle on the new one — a visible stutter on one tap. The
same move by SWIPE is clean, which is what makes it look like a rendering
glitch rather than a logic bug.

The button handler does two things: it sets the page state immediately, so the
header answers the tap, and then calls `scrollTo({ animated: true })`. That
animation fires `onScroll` every frame, and your handler rounds
`contentOffset.x / width` back to a page index — which for the first half of the
animation is still the page being LEFT. So the handler overwrites the state you
just set, then corrects itself on arrival. A finger never does this, because it
moves the offset itself and nothing sets the index ahead of it.

Filter the frames a programmatic scroll passes through:

```jsx
const animatingTo = useRef(null);

function goTo(i) {
  animatingTo.current = i;
  setPage(i);                                   // header answers the tap
  scroller.current?.scrollTo({ x: i * width, animated: true });
}

function onScroll(e) {
  const next = Math.round(e.nativeEvent.contentOffset.x / width);
  if (animatingTo.current !== null) {
    if (next === animatingTo.current) animatingTo.current = null;
    return;                                     // ignore the pages in between
  }
  if (next !== page) setPage(next);
}
// onScrollBeginDrag clears the ref: a finger beats an animation, and without
// this an interrupted animation leaves the header stuck forever.
```

**A screenshot cannot catch this** — the settled state is correct. Sample the
header during the transition instead, collapse consecutive duplicates, and
assert you see at most two values.

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

### Giving every screen a URL makes every screen reachable by every ROLE
The moment a linking config exists, each registered screen has an address, and
an address can be requested by anyone signed in. If one navigator holds the
screens for two populations — staff and members, teacher and student, admin and
customer — each can now land on the other's.

Nobody types these URLs. **A browser tab outlives the person signed into it.**
On a shared device the first user finishes on some deep page, signs out, the
next signs in, and the router restores the stored path under the new account.
Every query on that screen is then denied, one report per listener, from a
screen the app never offered.

Security rules still hold, so nothing leaks — which is exactly why this survives
review. What ships is the *wrong screen*, fully rendered: forms, action buttons,
headings addressed to someone else, all inert.

**Register only the screens a role may use, and build the linking config from
the same split.** A path outside the current role then matches nothing and the
container falls back to the initial route — their own home, which is the right
answer. Conditional children work directly:

```tsx
{isMember ? <Stack.Screen name="MyItems" …/> : <>{/* every staff screen */}</>}
```

Two follow-ons. A screen genuinely used by both goes in a shared table included
by each, so it is explicit rather than accidental. And an assertion that the
route merely *renders* is not enough — check the other role's URL yields their
own home, because "the screen is blank" and "the screen is forbidden" look alike.

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

### Text with `numberOfLines` PAINTS OVER its neighbour on device, invisibly on web
A `<Text numberOfLines={1}>` sharing a flex row with a sibling — an icon button,
a chevron, a count — needs **`flexShrink: 1`**. Without it Yoga measures the text
against the row's *full* inner width, then lays it out *beside* the sibling, so
the row's content is wider than the row. `numberOfLines` does not save you: the
text still truncates with an ellipsis, at the wrong width, so it looks
deliberate.

What makes it expensive is the platform split. **RNW gives `View` a default
`overflow: hidden`, so web clips the overrun and looks perfect.** Native `View`
defaults to `overflow: visible`, so on device the text is drawn *on top of* the
neighbouring control — a long title sitting across a "‹ Prev" button, which
reads as a rendering glitch rather than a layout bug. Every screenshot you take
in the browser will say the screen is fine.

Audit for the shape rather than the symptom: grep `numberOfLines` and check each
one is either `flexShrink: 1`, `flex: 1`, or the row's only child. Two details
worth deciding once:

- The **centred** variant is the one people forget — a `justifyContent: center`
  row still needs shrink, and it is easy to write `!center && styles.shrink`
  reasoning that centring somehow constrains the width. It does not.
- Where the text *is* the row, with empty space above and below it, prefer
  `numberOfLines={2}` with `textAlign: 'center'` over truncating at one line.

Prove it with geometry, not eyeballs: in Playwright, compare the text's
`getBoundingClientRect().right` against the sibling control's `left`. That check
is meaningful even on web, where the clipping hides the overlap.

**Comparing two elements to each other is safe; comparing one to the VIEWPORT
depends on the scrollbar, so measure before believing either story.**

Measured on Playwright's bundled headless Chromium on Linux: the scrollbar is an
**overlay**, and the inset is **zero** — at the document level and on an
`overflow-y: scroll` element alike.

```
viewport 320 · innerWidth 320 · documentElement.clientWidth 320
scroller rect 320 · scroller clientWidth 320 · inset 0
```

So on that runner `innerWidth` and the layout box are the same number and none of
this matters. `--disable-features=OverlayScrollbar` does **not** flip it back, so
do not spend time trying to reproduce the classic case there.

It matters where a **classic** scrollbar is in effect — another OS, a headed run,
a different browser — because it takes ~15px out of the layout box, and the two
common checks then fail in *opposite* directions:

| check | with a classic scrollbar |
|---|---|
| "is this column centred?" vs `innerWidth` | false **positive** — a centred column reads ~7px off |
| "does the page bleed?" as `scrollWidth - innerWidth` | false **negative** — under-reports, hiding up to ~15px of real overflow |

The false negative is the one to care about: a guard that quietly under-reports
still catches large overflows, so it degrades invisibly rather than going red.

Measuring against the layout box costs nothing and is right on both kinds of
runner, so just do it and stop thinking about scrollbars:

```js
const vw = Math.min(document.documentElement.clientWidth, window.innerWidth);
// and for a scroll container:
const inner = { left: el.getBoundingClientRect().left + el.clientLeft,
                width: el.clientWidth };
```

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

### A Gradle daemon plus emulators looks exactly like a broken diff
`expo run:android` leaves a Gradle daemon resident on roughly 3.7 GB. Start the
Firebase emulators on top of that on a Linux box running **earlyoom** — whose
default `--prefer` list includes `java` and `gradle` — and the OOM killer takes a
JVM. The one it takes is usually the Firestore emulator, mid-suite.

The reason this costs hours is that the symptom does not resemble memory
pressure. You get ECONNREFUSED and a wall of failed-and-skipped tests, which
reads as "my change broke the suite", so you go and audit your own diff. Nothing
in the output mentions memory.

Stop the daemon before starting emulators (`./gradlew --stop` in the test
script), rather than disabling it globally — that keeps the dev build loop fast
and costs only a cold Gradle start on the next build. Release builds should pass
`--no-daemon` anyway; it is the DEBUG path that leaks one.

Two projects hit this independently before either of us worked out what it was.

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

An **organization** auth token (`sntrys_…`) reaches every project in the org, so
reuse one across apps and surfaces rather than minting per project; only the
project differs. Scope it to CI/release permissions only — a token that cannot
read the org is the right shape for a build secret, and you can confirm what it
holds by probing: release endpoints answer `200` while org-level ones answer
`403`. Sentry shows a token's value **once**, at creation, so whatever copy you
saved is the only one.

Where that token lives — a gitignored properties file or the environment — is a
real choice with real trade-offs; see below.

### `@sentry/react-native` source maps need a release build AND the Gradle plugin
Native upload only runs on `assembleRelease`, and only if the Sentry Gradle
plugin is applied — which the config plugin does at `prebuild`. In the bare
workflow (committed `android/`, no prebuild) a `sentry.properties` alone uploads
nothing. Runtime error *reporting* still works; only symbolication waits. This is
a first-release concern, not a first-wire one.

**The remedy, since the config plugin can never reach a committed `android/`:**
apply the package's own Gradle script by hand, and gate it on the token so a
machine without one builds exactly what it built before.

```gradle
// android/app/build.gradle, above the react block
if (System.getenv("SENTRY_AUTH_TOKEN")) {
    apply from: new File(["node", "--print",
        "require.resolve('@sentry/react-native/package.json')"]
        .execute(null, rootDir).text.trim(), "../sentry.gradle")
}
```

The gate is not politeness. Without it the release path acquires a dependency on
reaching sentry.io, and a network blip fails a build that has nothing to do with
Sentry. With it, absence is a no-op.

**Prove the gate rather than assuming it**, because both states look like a
successful build:

```sh
./gradlew :app:tasks --all -q | grep -c SentryUpload   # 0 without, ≥1 with
```

Expect `0` with no token and a `…_SentryUpload_…` task with one. The task name
also contains the release it will upload under — check it matches what the SDK
reports at runtime, or the maps attach to a release nothing was reported against.

### An iOS config plugin writes its options into the app package
Register `@sentry/react-native/expo` (or equivalently `@sentry/react-native` —
`app.plugin.js` is one line re-exporting it) **bare, with no options**. Given
`organization`/`project` it writes them verbatim into `ios/sentry.properties`,
and its own source warns that an `authToken` option "will be written to the
application package". Bare, it falls back to `SENTRY_ORG`, `SENTRY_PROJECT` and
`SENTRY_AUTH_TOKEN` from the build environment — which is also how `sentry-cli`
reads them on the Android side, so one set of names covers both platforms.

### Where to keep the token: a file or the environment, and why it is a real choice
Both are defensible and the failure modes differ, so pick one per repo rather
than drifting into both:

- **A gitignored `sentry.properties`** keeps the token out of your shell history
  and out of every child process's environment. `SENTRY_PROPERTIES=<path>` points
  the CLI at it.
- **Environment variables** cannot be committed by accident. In a **public** repo
  that is the deciding argument: a gitignored secret is one `git add -f` or one
  careless `.gitignore` edit away from permanent publication, and a public repo's
  history cannot be unpublished.

Two mechanisms for the same three values is the outcome to avoid — they drift,
and the one you are not looking at is the one that is stale.

### Renaming a Sentry project breaks `SENTRY_PROJECT`, not the DSN
A DSN carries the **numeric** project id, so renaming a project's slug does not
affect any shipped app: no rebuild, no redeploy, no client config change.
`sentry-cli` addresses projects by **slug**, so `SENTRY_PROJECT` must follow in
every build shell and CI config the moment you rename.

Worth knowing because the natural first name goes stale: a project called
`…-android` starts receiving iOS events the day an iOS target appears, and the
name then actively misleads whoever reads the next crash report.

### Never backfill source maps for an already-shipped build
Rebuilding an old version to "add the maps we forgot" produces a *different*
bundle unless the tree is byte-identical — and a stamped commit hash alone is
enough to change it. The maps upload against that version's release name, so
Sentry then symbolicates the shipped build to lines from a bundle nobody is
running, confidently and with no warning.

That is worse than no maps at all: unsymbolicated frames announce themselves,
wrong ones do not. The first upload belongs to the next release.

### "Slow operation" alerts that are really the file picker or the document viewer
A wrapper that times a user action from tap to settle will charge it for time the
app was not even on screen. Every expo module that shows system UI resolves its
promise from `onActivityResult`:

| API | Held until |
|---|---|
| `DocumentPicker.getDocumentAsync` | a file is chosen, or the user backs out |
| `ImagePicker.launchCameraAsync` | the shot is framed, taken and confirmed |
| `IntentLauncher.startActivityAsync` | the viewer activity **finishes** |
| `Sharing.shareAsync` | the chooser is dismissed |

`IntentLauncherModule.kt` and `SharingModule.kt` both stash the promise before
`startActivityForResult` and resolve it from the result callback — so "open this
PDF" does not settle until the reader closes the PDF. Measured on an emulator: a
file attached after ~33s in the picker reported `took 37992ms`; a document left
open 21s reported `took 20935ms`, exactly **100ms after Back was pressed**; a
camera attach with permission and framing ran 104s. A *cancelled* pick reported
too — a slow write for a write that never happened.

The trap is that the wrapper is usually right. Timing a whole action is correct
for a database write, and the same wrapper typically also drives a `busy` flag —
which *should* cover the picker, so the control stops taking taps. The two spans
look like one and are not.

```ts
// The callback gets a helper for regions whose duration is not yours.
await run(async (untimed) => {
  const picked = await untimed(() => pickAttachment(source));   // a human
  if (!picked) return;
  await setDoc(ref, meta);                                      // charged
  await untimed(() => uploadBytes(ref, picked.blob));           // size, not you
  await finalize({ id });                                       // charged
});
```

Exclude the byte transfer for the same reason as the human: its duration is set
by file size and uplink, and a flat threshold written for a metadata write is the
wrong instrument. What is left charged — writes and callables — is the part that
should be fast regardless, which is the property worth alerting on. Report the
excluded total alongside, so a report is not quietly hiding time.

**The tell that this is your bug and not real latency:** the breadcrumbs show
`MainActivity` going `created → started → resumed` shortly before the report,
with `Running "main"` alongside. That is the activity being re-created on the way
back from the picker, not an app restart.

Do not answer it by raising the threshold. That is the tempting fix, it works
once, and it leaves you tuning a number against a measurement you know is wrong.

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

### Signing out does not unsubscribe first, so the exit raises a denial
Firestore re-issues every live listen the instant the credential drops, and the
server refuses them — while the framework is still unmounting the screens holding
them. The result is a `permission-denied` reported from whatever screen the user
was on when they left, which is usually the one carrying the Sign out button.

It is not a defect: with no usable session every rule denies by design, so a
denial in that state carries no information. Publish a flag from the auth
callback — it runs in the same tick the credential changes, long before a server
refusal can return over the wire — and have the listener error path consult it:

```ts
onAuthStateChanged(auth, (user) => { setSessionCanRead(false); /* …then resolve */ })
// and where claims are published:
setSessionCanRead(!!profile && claims.status === 'active')
```

Cover the gated states too, not just signed-out. Being **disabled mid-session**
is the same shape — the claim flips under a screen that is still subscribed.

Keep it narrow, or it becomes the thing that hides the bug you needed: suppress
only `permission-denied`/`unauthenticated`, only while the account provably
cannot read. A denial to a signed-in, ACTIVE user is the interesting kind. Prove
the scoping by re-running a known real denial with the guard in place and
watching it still report.

### Report YOUR message for a listener error, not the SDK's
Hand `captureException` the raw `FirebaseError` from an `onSnapshot` error
callback and every live subscription in the app collapses into **one** issue,
titled `Missing or insufficient permissions`, over a stack of minified SDK
internals (`__PRIVATE_fromRpcStatus`, `PersistentListenStream#onNext`) that names
no screen, no collection and no query. It is unactionable: you cannot tell which
of two dozen subscriptions produced it without guessing.

If your live-data hook already takes a label — and it should, for the on-screen
error — put the label in the **title**, not only in a tag. Tags are per-event;
grouping is per-message, and grouping is what you read:

```ts
captureError(new Error(`Live data error (${label}): ${e.code}`),
             { source: label, code: e.code ?? 'none', detail: e.message });
```

The SDK frames were never worth reading; the label and the code are the entire
diagnostic. Same reasoning as sending the uid instead of the email — decide what
triage actually needs and send that, rather than forwarding whatever the library
handed you.

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

### The MODULE still autolinks — you probably do not need a prebuild
Easy to over-correct from the above and conclude that adding a notifications
library to a bare workflow means regenerating `android/`. It does not. Config
plugins and native modules arrive by different routes:

- **The module** is picked up by expo-modules autolinking at Gradle time, from
  `package.json`. No prebuild involved.
- **The config plugin** is what needs prebuild — and for a notifications library
  it typically contributes only a default notification icon and colour.

So `npx expo install <notifications-lib>` and rebuild. Do not take
`BUILD SUCCESSFUL` as proof it linked; grep the merged manifest, where the
library's own services will have been merged in:

```bash
grep -o "com.google.firebase.messaging[A-Za-z.]*" \
  android/app/build/intermediates/merged_manifest/debug/*/AndroidManifest.xml
```

Absent means autolinking did not see it. Present means the receiver that will
wake your app is registered — which `BUILD SUCCESSFUL` never told you.

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

### Web push: `register()` resolving is not a worker running
`navigator.serviceWorker.register()` resolves when the script has been
**fetched**, not when a worker is active. Hand that registration to `getToken`
and it throws:

```
AbortError: Subscription failed - no active Service Worker
```

Only on a first-ever visit — every later load already has one activated, so it
reproduces for new users and never for you.

```ts
await navigator.serviceWorker.register('/firebase-messaging-sw.js');
const registration = await navigator.serviceWorker.ready;   // ← the one to pass
```

And bound it. **`ready` never rejects**: a worker that fails to activate leaves
it pending forever, so a naive await gives you a settings screen stuck on
"checking" with no error and no notice — worse than either success or failure,
because it looks like it is still working.

```ts
const registration = await Promise.race([
  navigator.serviceWorker.ready,
  new Promise<null>((r) => setTimeout(() => r(null), 10_000)),
]);
if (!registration) return null;
```

### You cannot mint a web push token in Playwright — do not read that as a bad key
Two independent walls, and both look exactly like a rejected VAPID key:

- **Headless** leaves `Notification.permission` reading `"denied"` however
  `requestPermission()` resolves, and the SDK reads the property:
  `messaging/permission-blocked`. Headed under `xvfb-run` reports `granted`.
  This is Playwright's default `headless_shell` build, which disables
  notifications outright — no CDP `Browser.setPermission` call moves it.
  `chromium.launch({ channel: 'chromium' })` (the full browser, new headless)
  reports `"default"` instead, which is the state that renders a "turn these
  on" control — so that is the launch you need to screenshot the offer, even
  though it still cannot mint a token.
- **Playwright's Chromium is the open-source build**, which ships without the
  Google API keys needed to reach FCM's push service:
  `AbortError: Registration failed - permission denied` from
  `PushManager.subscribe`. `channel: 'chrome'` does not rescue it either.

So web delivery has no automated check — but the **permission-dependent UI** is
a different question, and that one you can automate. The state machine under test
is yours, not Chromium's, so replace the getter and drive it:

```js
await ctx.addInitScript(() => {
  Object.defineProperty(window.Notification, 'permission', {
    configurable: true, get: () => 'default',   // or 'granted'
  });
});
```

That is what makes an offer card render in a layout sweep at all — headless
reports `"denied"`, so a card shown only while the device can still be asked is
absent from every screenshot at every width, and the sweep that exists to catch
its layout cannot see it. It also lets you assert the foreground re-read: change
the getter, dispatch `visibilitychange`, and require the panel to move to a
different message. Mutation-check that one — drop the subscription and watch it
go red — because a check that waits for a message already on screen passes
without anything having happened.

What you CANNOT fake this way is delivery. What you CAN automate, with no browser
at all:

```js
// A VAPID public key is an uncompressed P-256 point: 65 bytes, leading 0x04.
const raw = Buffer.from(key.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
ok(raw.length === 65 && raw[0] === 0x04);

// And a send to a bogus token proves FCM authenticated you AS THIS PROJECT —
// Cloud Messaging disabled or wrong credentials fail differently and earlier.
const res = await admin.messaging().sendEachForMulticast({ tokens: [bogus], … });
ok(res.responses[0].error?.code === 'messaging/registration-token-not-registered');
```

That second assertion doubles as a check on your prune list: it pins the dead-token
code to one FCM really returns, rather than one copied from documentation.

Android is different — an emulator with Google APIs mints a real token and
receives a real notification, so the whole chain **is** verifiable there. Do that
before concluding anything about your server code from a browser failing.

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

### Web push needs a THIRD thing: the prompt must follow a click
Permission is not configuration, and it is the part a browser refuses on your
behalf without telling you. `Notification.requestPermission()` **consumes
transient activation** in WebKit, which honours it only as the direct result of a
click. Asked from anywhere else:

- **Safari** refuses outright — no prompt, the promise resolves `"default"`.
- **Chrome** demotes it to the quiet chip, easily missed, and records no decision.

Either way `Notification.permission` stays `"default"`, so **the site appears in
neither the allowed nor the blocked list**. That absence is the diagnostic — a
site genuinely refused is in the blocked list.

The wrong call sites all look reasonable:

- a sign-in callback, or a Firestore `onSnapshot` handler;
- a `useEffect` keyed on the signed-in user;
- a `useEffect` on the settings screen someone just tapped into. **Navigation is
  not activation** — React flushes passive effects in a later task than the tap,
  so the gesture is gone by the time the effect runs.

And inside a click handler, **nothing may be awaited before the request** —
including the support check:

```ts
// WRONG. isSupported() awaits an IndexedDB open() that resolves from an
// `onsuccess` TASK, so the request lands an event-loop turn after the click.
if (!(await isSupported())) return;
if ((await Notification.requestPermission()) !== 'granted') return;
```

Split the check by synchrony. The synchronous half gates the prompt; the
asynchronous half runs after it, where an await costs nothing:

```ts
function canRequestPush(): boolean {
  return (
    !!VAPID_KEY && typeof window !== 'undefined' &&
    'Notification' in window && 'serviceWorker' in navigator &&
    'PushManager' in window
  );
}

export async function enablePush(uid: string) {
  if (!canRequestPush()) return 'unavailable';
  // Inside the try, and still first: ENTERING a try block is synchronous, so
  // this keeps the request in the click AND catches a synchronous throw. Left
  // outside it, a throw escapes a function every caller treats as total, and
  // the button it was pressed from spins for ever.
  try {
    // NOTHING MAY BE AWAITED ABOVE THIS LINE. An async function runs
    // synchronously up to its first await, so the request below is still inside
    // the click — provided every caller in the chain also calls straight through.
    const decision =
      Notification.permission === 'default'
        ? Notification.requestPermission()
        : Promise.resolve(Notification.permission);
    if ((await decision) !== 'granted') return 'denied';
    if (!(await isSupported().catch(() => false))) return 'unavailable';
    // ...service worker + getToken, awaits are free from here
  } catch {
    return 'unavailable';
  }
}
```

And where the caller catches, map the rejection to the FAILURE outcome, not to
`undefined` — `undefined` falls through whatever branch handles success and the
card vanishes silently, which is the thing the three outcomes exist to prevent.

```ts
enablePush(uid).catch(() => 'unavailable' as const).then(/* … */);
```

The shape that works: **sign-in registers silently when permission is already
granted** — `getToken` never prompts in that state, so every already-working
device keeps working with no click — and a **"Turn on notifications" button** on
the settings screen is the only thing that ever asks.

Return three outcomes, not a boolean. Granted-but-no-token (pointed at the
emulators, a worker that failed to activate) is not a refusal, and telling
someone notifications are "turned off" when they just said yes sends them to fix
a setting that is already correct.

**Do not gate the UI state on the emulator flag.** Registration must skip the
emulators — FCM has none — but folding that into the capability check makes the
whole screen read "unsupported" in every local run, so the one control the
feature depends on can never be seen, screenshotted or toured by a layout sweep.
Gate the token, not the screen.

**On native the same gate has a second victim, and it is worse.** Put
`if (USE_EMULATORS) return false` on the first line of the registration function
and you also skip the permission request and the channel creation — so an
emulator-backed build can never once raise the OS dialog or create the channel.
That is the only build most projects can put on a device, which leaves the one
native surface a browser cannot reach unreachable from the only place it could
be looked at, and the channel's importance unverifiable. It also makes the
enable-path lie: registration returns false, the caller re-reads a permission
nobody asked for, finds "default", and reports **denied** for a device that has
simply not been asked — so the offer card hides on a press that did nothing.
Put the gate immediately above the token call, with the channel setup and the
prompt above it. Everything but delivery is then real on a local build, and
`adb shell dumpsys notification` will show you the channel and its importance.

**react-native-web is safe here**: `PressResponder` invokes `onPress`
synchronously inside the DOM `click` handler, so a `Pressable` does carry the
activation. Worth confirming rather than assuming — it runs its own responder
state machine full of `setTimeout`s.

**A keyless build deletes the whole path, silently.** The key reaches the bundle
from `EXPO_PUBLIC_*` in the environment that runs `expo export`. Miss it and
nothing fails — an inert-by-design client means the build succeeds, the site
deploys, and every device reports it cannot receive notifications. It is
invisible in source, because the source is correct either way. It is glaring in
the OUTPUT: with no key the minifier proves the capability check false and folds
the entry point to a bare `return'unavailable'`, deleting the permission path.
Gate the release on reading the exported bundle — assert a real 65-byte P-256
point (87 base64url chars, leading `B`, and NOT the Firebase SDK's own sample
key `BDOU99…`). Keep it out of `web:export` itself: keyless local builds are
normal, and the e2e harness depends on them.

**Put the ask somewhere it will be found.** A control that only exists on a
notification-settings screen is a fix nobody reaches. A dismissible card on the
first screen after sign-in works, and dismissing it costs nothing — that is the
whole point of asking on your own card before the browser's: a "not now" there
is free and repeatable, while a dismissed browser or OS dialog is spent. Under a
STACK navigator, check on focus rather than on mount: the home screen stays
mounted while settings is pushed over it, so someone who enables notifications
there returns to a card still insisting they are not enabled.

**A headless e2e cannot catch a regression in this** (see the Playwright note
below), so assert the shape in a unit test: mock `isSupported()` to a promise
that never resolves, call the handler entry point, and assert
`requestPermission` was still called. That fails on any reintroduced await.

### Android lets you prompt from anywhere, so nothing stops you asking at the worst moment
The web half of this is enforced for you: a browser refuses a request that does
not follow a click, so the bug announces itself. Android honours a request from
anywhere — including a sign-in callback — so the same code "works" and ships,
and the port of the click-driven design stops at the platform boundary with a
comment saying native needs no such rule.

It needs the rule for a different reason. **Android 13's notification permission
is spendable**: a second refusal fixes it permanently, and nothing in the app can
raise it again. So where the prompt lands matters as much as whether it appears.
Asking from the sign-in path lands it on whatever screen happens to be up at the
time — for an app with an approval gate, that is a *waiting to be approved*
screen, where the account cannot yet see anything and there is nothing to be
notified about. It is the least persuasive moment available, and it is one of
only two you get.

It also makes the offer card pointless on that platform: by the time the first
screen renders, the OS has already asked, so the card either shows a stale
message or double-asks — spending the second chance on a screen the person did
not press anything to reach.

Same shape as web, and for a stronger reason: sign-in reads the permission and
registers **only if it is already granted**; one button asks. On Android that
costs a tap and buys back both prompts for a moment the person chose.

Watch it on a device rather than reasoning about it — `adb shell dumpsys package
<pkg> | grep POST_NOTIFICATIONS` prints the flags. Nothing asked yet has no
`USER_SET`; one refusal adds `USER_SET`; a spent prompt adds `USER_FIXED`. That
is the whole state machine, readable at any point, and it is how you tell "we
never asked" from "they said no".

### Returning from the OS settings screen re-runs nothing
Tell a blocked device to open system settings and you have sent the person out
of the app. They turn notifications on. They come back. The screen still says
**blocked**, beside the same button back to the setting they just fixed — a
closed loop whose only exit is navigating somewhere else and back, which the
screen never suggests. `dumpsys` says `granted=true` throughout, so nothing looks
broken anywhere except on the screen.

Nothing remounts on that return. It is not a navigator event, so checking on
focus does not cover it either — that fixes a *pushed screen* hiding a mounted
one, which is a different problem with the same symptom. What actually changed is
that the app came back to the front:

```ts
useEffect(() => {
  const check = () => { /* re-read permission, set state */ };
  check();
  const sub = AppState.addEventListener('change', (s) => { if (s === 'active') check(); });
  return () => sub?.remove();
}, [uid]);
```

One implementation covers both surfaces: react-native-web maps `AppState` onto
`document.visibilitychange` and emits `currentState` with no diffing, so a
browser tab returning from its site-settings panel re-reads the same way. Make
the check cancellable — it is async and sets state when it lands, so two
foregrounds in quick succession otherwise leave two live checks racing.

This generalises past notifications: any state the app does not own and cannot be
told about — an OS permission, a system setting, a subscription bought
elsewhere — needs re-reading on foreground rather than on mount.

### A tap that only opens the app is a half-built notification
A push that names a specific record ("X was rejected", "Y is waiting for you")
and then drops the user on the home screen has made them go find it themselves.
Send the destination with the message.

The two surfaces consume it completely differently, and only one of them can be
handed a payload:

- **Android**: an FCM `data` map (string→string), read from the tapped response.
- **Browser**: nothing. A web push click can only *open a URL* — set
  `webpush.fcmOptions.link` and put the destination in its query string.

So encode the destination as flat string key/values once, and let the web
transport re-read the identical keys off `location.search`. One encoder, one
strictly-validating decoder, both surfaces — and the browser path is then
testable in a normal e2e run by simply visiting the URL, which is the only way
you will ever exercise this logic without a real device (see below).

### `data.body` is intercepted by expo-notifications and eats the whole payload
`expo-notifications` inspects one FCM data key by name. In
`NotificationSerializer`, if `data["body"]` parses as JSON it is treated as the
*entire* JS payload — every sibling key is dropped — and otherwise the flat map
is copied through as `content.data`. Both paths work; mixing them does not.

Pick one and never name a data key `body`. The failure is silent: your other keys
simply aren't there at runtime, on the device only.

Also unavoidable on Android: the same tap can be reported **twice** on a cold
start — once by `getLastNotificationResponseAsync()` (the tap that launched the
app, collectable only after the fact) and once by the response listener. Dedup on
`request.identifier`.

### A cold-start tap arrives before anything is navigable
The tap happens before any JS exists. By the time you can read it, auth is still
restoring, the profile has not loaded, and the navigator is not mounted — so
navigating immediately does nothing, or throws.

Queue the destination and release it only when the navigator is ready *and* the
session is known. And check the destination is still reachable: a screen that is
conditionally registered (manager-only, admin-only) does not exist for a demoted
account, and navigating to a name the navigator doesn't have throws.

One more, once routing works: navigating to a screen that is **already mounted**
updates its params rather than remounting it. Any screen that seeds state from a
param (`useState(initialKey)`) will ignore the new one and leave the user on the
previously targeted record. Sync the param into state with an effect.

### What you cannot verify yourself
No emulator delivers a push. FCM has no emulator, and an Android emulator without
Play services will not receive one. Registration, rules and pruning are all
testable; **arrival is not**. Say so explicitly rather than reporting the feature
as done.

The *routing* half is a different matter and is fully testable without delivery:
drive the web build with the route in the query string (e2e), and on a device
schedule a **local** notification carrying the same payload, then tap it. That
covers the listener, the decode, the queue and the navigation — everything except
FCM's own hop, which is exactly the part no test can reach.

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

### Your cleanup missed the documents that have no document
Listing a collection returns its **documents**. A path that exists only as the
parent of a subcollection is not one of them — Firestore has no requirement that
`users/{uid}` exist for `users/{uid}/devices/{token}` to. So the usual
between-tests cleanup —

```ts
const snap = await db.collection('users').get();
await Promise.all(snap.docs.map(async (d) => {
  const kids = await d.ref.collection('devices').get();   // never runs for a
  await Promise.all(kids.docs.map((k) => k.ref.delete())); // parentless path
  await d.ref.delete();
}));
```

— silently leaves behind exactly the rows belonging to the users who have a
subcollection and no document, which is the interesting population: the ones who
never touched the screen that creates the parent.

The leftovers then make the NEXT test look like a code bug — an idempotency
marker that appears already claimed, a device list that is longer than it should
be. The console shows them (it renders parentless paths in italics); a list query
does not.

```ts
await db.recursiveDelete(db.collection('users'));   // Admin SDK
```

Same trap when counting: a "how many users have registered a device" query
against the parent collection undercounts for the same reason.

### Test files sharing one emulator must not run in parallel
Two test files that each call `clearFirestore()` in `beforeEach` will wipe each
other's seed mid-run when the runner parallelises files. The failures are
plausible-looking permission denials and missing documents, they move between
runs, and each file passes alone — which reads as flakiness in the emulator
rather than in the invocation.

Runners default to parallel. Pin it in the script, not in your memory of how to
invoke it: `vitest run --no-file-parallelism`. If a suite passes file-by-file and
fails together, check this before anything else.

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
- **Redundant guards make a single mutation lie.** Break one of two guards that
  each cover the case alone and the suite stays green — which reads as "the test
  is vacuous" when the test is fine. Mutate back to the shape that actually
  shipped, all guards at once. Two separate single-guard mutations both came back
  green before the combined one turned red at the real defect.

### Your browser harness collects console.error and misses console.warn
A failed live subscription typically ends up at `console.warn` — the SDK's own
listener errors do, and so does most hand-written reporting around them. A
harness that collects only `console.error` is blind to every one of them, and
these are exactly the failures that render as an ordinary empty state, so no
outcome-based check notices either.

Collect a run-wide list of them across every page, and fail on any:

```js
page.on('console', (m) => {
  if (m.type() === 'warning' && / listener\b/.test(m.text())) denials.push(m.text());
});
// …at the end
check('not one live subscription was refused in the whole walkthrough', !denials.length);
```

A denial is never correct in a flow the app itself drives, so this needs no
per-screen knowledge and catches denials on screens no check ever reads. Where
some are genuinely expected (a session ending — see the sign-out entry above),
have the app MARK those in the log line and exclude the marked ones, rather than
loosening the check.

### A new test file is never run, and the totals hide it
A suite invoked by an explicit file list — `vitest run test/a.test.ts test/b.test.ts`
— silently ignores anything you add. There is a reason to list files (different
emulator sets per pass, avoiding trigger cross-talk), so the fix is not globbing:
it is a test that reads the package script back and fails if any file on disk is
missing from it.

```js
const listed = `${pkg.scripts['test:integration:rules']} ${pkg.scripts['test:integration:fn']}`;
const missing = readdirSync('test/integration')
  .filter((f) => f.endsWith('.test.ts') && !listed.includes(`test/integration/${f}`));
expect(missing).toEqual([]);
```

The signature is nasty because **nothing looks wrong**: the run is green, and the
file and test counts are unchanged — which reads as "my change added no tests"
rather than "my tests did not run". Compare counts before and after adding a
suite; if they did not move, the suite is not running.

### Anything you render near a focused input is probably behind the keyboard
A keyboard-aware scroller positions the FOCUSED element and nothing else. Two
symmetrical failures follow, and neither is visible from the code:

- **Below the input**: the scroller leaves a fixed offset under the field (enough
  for its submit button, no more). An autocomplete or hint rendered in that gap
  is simply under the keyboard. Symptom: you type `@`, see the list's *heading*
  and no rows at all.
- **Above the input**: content inserted above a field that is ALREADY focused
  pushes it down, and the scroller does not re-run — so the list is visible and
  the box you are typing into is not.

The fix for both is to take the popover out of layout: `position: 'absolute'`
with `bottom: '100%'` on a wrapper around the field. The field never moves from
where the scroller put it, and the list floats over whatever is above.

```tsx
<View>                                  {/* relative by default */}
  {open ? <View style={{ position: 'absolute', bottom: '100%',
                         left: 0, right: 0, zIndex: 10, elevation: 8 }}>…</View> : null}
  <TextField … />
</View>
```

`zIndex` AND `elevation` — web/iOS stack on the first, Android on the second.

**Screenshot each attempt on a device.** All three states here — invisible below,
field-hidden above, correct as a popover — looked equally fine in the source.

### A nested ScrollView needs its own `keyboardShouldPersistTaps`
It is not inherited from the screen's scroll view. Without it the first tap on a
row while the keyboard is up only dismisses the keyboard; the press never fires
and the row reads as dead. A picker opened from a BUTTON never shows this,
because no keyboard is up — so the bug only appears in the one list that is used
while typing, which is the one nobody thinks to re-check.

No automated test can catch its removal on web, because web has no soft
keyboard. Say so out loud rather than implying the suite covers it.

### `data ?? []` turns "not loaded yet" into "empty", and validation waves it through
A live-query hook that reports `data: undefined` for BOTH the loading and the
error state makes `?? []` a trap at any call site that validates against the
list: a uniqueness check against an empty array always passes.

```ts
// Wrong — silently permits a duplicate while the list is still in flight
const problem = validateName(name, list.data ?? []);

// Right — the control stays disabled until the check can mean something
const known = list.status === 'ready' ? list.data : null;
```

The ERROR case is the sharp one. Loading is a window measured in milliseconds;
an errored listener is permanent, and the same screen usually renders an empty
picker too — so the user cannot even see what they are duplicating.

### Overlapping notification audiences: precedence decides whose PREFERENCE wins
When one event can reach the same person through two routes (assigned to it,
subscribed to it), you de-duplicate by picking one route and excluding the
other — and that choice silently decides which preference applies. Get it
backwards and an explicit per-item opt-in is swallowed by a global default the
user turned off, so the button they pressed does nothing and nothing explains it.

**The narrower, hand-made choice must win.** A per-item subscription outranks a
blanket "everything assigned to me" setting. Make the message text identical for
both routes so the ordering has no other visible effect, and assert it: reverting
the precedence should turn exactly one test red.

### One screen, two queries: don't let the secondary one take down the primary
Adding a second list to a screen usually means widening the loading and error
gates to cover both. That quietly makes a failure in the *new* list fatal for the
*existing* one. Gate the error on whichever list is actually being viewed.

And when showing a count for the list you did NOT block on, never render 0 for a
query that errored — show "?" or nothing. "Not loaded" is not "empty", and a
zero is indistinguishable from a real answer.

### A new "who cares about this doc" list is a new READ grant
The moment a cross-collection list ("things I follow") appears in the UI, the
query has to be authorized from its own constraint — rules cannot prove anything
about an unconstrained `collection('things')`. So the field gets an arm in the
read rule, and that arm IS an access grant.

Whatever the existing membership-style field does, the new one must do too:

- constrained to people who could already read the doc (else it is a way in),
- **cleared when someone loses access** — the removal path already clears the old
  field for exactly this reason, and forgetting the new one is a silent leak,
- filtered when the doc moves to a different parent,
- and absent from a copy, if the thing being followed is not copied.

Mutate each one and watch a test go red; the "cleared on removal" case is the one
with no visible symptom until someone leaves.

### Adding a filter to an existing query can need a composite index
`where('parentId','==',x).where('followers','array-contains',u)` is an equality
plus an array-contains, which automatic single-field indexes do NOT serve. It
works in the emulator (which does not enforce composites) and fails in
production. If a comparable pair already exists in `firestore.indexes.json`, that
is the tell: add the mirror image and a probe at the same time.

### Closing an autocomplete on blur destroys the click that was about to pick
A click fires **mousedown → blur → click**. Hide the list on blur and the row is
gone before the click lands, so picking silently stops working — you trade a
popover that lingers for one that cannot be used.

Defer the close (~200ms) and let a focus cancel it. If the pick already refocuses
the input, it cancels its own pending close for free.

The two behaviours are one change and must be asserted together: "clicking away
closes it" AND "clicking a row still picks". Mutating the grace period to zero
should turn the SECOND one red — if it does not, the pick is not really covered.

### A test that restates a constant drifts from it
A script that writes out `timeZone: 'America/New_York'` — even with a comment
explaining the bug it was added to fix — keeps saying that after the app's
`ORG_TIMEZONE` moves. The result was an assertion that could not pass between
23:00 and midnight local: the test wrote tomorrow's date and the app grouped the
card under "next 7 days".

Import the app's own function (`todayInOrgTz()`), do not re-derive it. And when a
check fails twice and passes once on identical code, measure before calling it a
flake — print what each side actually computed. This one was one `node -e` away
from obvious for weeks.

### A shared email domain makes substring matching useless
Any people-picker that matches on the whole email address will match EVERYONE in
a single-domain organisation: every letter of `acme.com` appears in every
address, so typing `@a`, `@c`, `@m`, `@o` or `@e` narrows nothing. Match the
local part (the handle) and the display name; the local part is what the address
adds anyway.

While there: rank matches at the START above matches in the middle, or "s" puts
*Fai-s-al* above *Sara* and looks broken.

### Scroll targets must use the row PITCH, not the row height
`scrollTo({ y: index * ROW_HEIGHT })` drifts by one gap per row whenever rows
have a margin. Four pixels is invisible at row two and most of a row by row
twelve, so the far end of a list scrolls to the wrong item. Derive one
`ROW_PITCH = ROW_HEIGHT + ROW_GAP` and use it for the row, the scroll and the
height cap.

And do not FIX the row height at all: text scales with the reader's system font
size, so a fixed height clips names at large accessibility settings. Use a
minimum and measure the real pitch from the first row's `onLayout`.

### Key repeat is faster than a render
Held arrow keys fire about every 33ms; React re-renders in about 16. Two moves
can land against the same state value, so the highlight moves one step instead
of two and the list feels like it is sticking. Same fix as any state-vs-frame
race: keep a ref alongside and read it in the handler.

### An ordering guarantee is invisible on the happy path
"Do A before B so a failure between them is recoverable" cannot be tested by
asserting the end state: on success both orders end identically. Reversing them
left an entire 251-test suite green.

Extract the operation and inject the first step so a test can make it throw:

```ts
export async function applyDelete(id, actor, sweep = realSweep) {
  const n = await sweep(id, actor);   // fails here → the record survives
  await db().doc(`things/${id}`).delete();
  return n;
}
```

That one parameter is the whole difference between a documented guarantee and an
enforced one. Any comment of the form "ORDER MATTERS" is a prompt to check
whether a test would actually notice it being reversed.

### Redundant guards make a single mutation lie
Mutation-testing one guard at a time reports "the test is vacuous" whenever two
guards each cover the case alone. Break the ref-gate: green. Break the disabled
state: green. Break both — the shape that actually shipped — and it goes red at
the real defect. **Mutate back to the shipped state, not one line of it.**

### A failed functions build leaves the emulator running the PREVIOUS code
The functions emulator serves the built bundle, and `build` is
`tsc --noEmit && esbuild`. When tsc fails, esbuild never runs and **the old
bundle stays on disk** — so `emulators:exec` starts happily and the tests run
against the last version that compiled.

This is lethal to mutation testing, and it fails in the direction that reassures
you. Deleting a call in order to mutate it orphaned that call's import, tsc
errored, the bundle kept the ORIGINAL code, and the test went **green** — which
was then read as "this test cannot detect the bug" when the truth was "the bug
was never in the binary". The conclusion was the exact opposite of the fact.

- **Check the build's exit code.** `npm run build >/dev/null 2>&1` followed by a
  test run is a lie waiting to happen: a mutation whose build failed is not a
  result, it is a skipped experiment.
- **Prefer type-clean mutations** — change a value (`filesRemoved: 0`), do not
  delete the call. Deletions orphan imports and take the build down with them.
- A green mutation means something only once the mutated code is proven to be
  the code that ran.

The nastiest part is that it poisons only HALF a suite. Tests that
`import { thing } from '../../src/thing'` execute the TypeScript **source** in
the test process and mutate correctly whatever the build did; tests that drive a
**trigger or callable** go through the emulator's bundle and silently go stale.
So the same mutation run reports honest failures for the in-process tests and
false passes for the trigger tests, in one output, and the mixture reads as "my
trigger test is weak".

General form: before concluding a test is wrong, confirm the artefact under test
is the artefact you edited — and know which artefact each test actually loads.

### …and the worse sibling: nothing built it at all
The entry above assumes a build ran and failed. Check the likelier case first:
**`firebase emulators:exec` does not build anything.** If the script that starts
the emulators does not build the functions itself, the triggers under test are
whatever was last compiled — possibly days ago, possibly by a different branch.

It presents identically to the failed-build case except there is no error to
find, so you go looking for a tsc failure that never happened. And it never goes
red on its own: the suite passes against yesterday's triggers exactly as
confidently as against today's.

Symptom worth recognising: an in-process test and a trigger test disagree about
the same change, the in-process one being right. That is the same half-poisoned
suite as above, from a different cause.

```bash
# in the script that starts the emulators, before emulators:exec
npm run build -w <shared-package>
npm run build -w functions
```

Cheap check on any repo you did not write: compare the mtime of
`functions/lib/index.js` against `functions/src`. If the bundle is older, every
trigger assertion in that suite has been decorative.

### Wait on the EVENT, not on a number derived from it
`waitFor(() => total === before - 64)` passed against code that recorded
nothing. A value that never moves cannot satisfy an equality wait — it can only
time out — so the assertion carried no information about whether the work
happened, only about how long it took to give up. Polling instead for *"the
counter increased"* fails immediately and names the event that never fired.
**Wait for the thing that should occur; assert the arithmetic separately.**

### Read production before designing a migration
Querying the real data first turned a merge into a union: no two boards used the
same label name and every embedded id was already globally unique, so each id
could become the new document id and **no referencing row had to be rewritten**.
The generalisable move is to check whether your existing ids can be reused as the
new keys — if they can, the migration stops touching the referencing collection
entirely, and old and new clients can both keep working while it runs.

Split any such migration in two: create the new records first (invisible, old
clients unaffected), deploy, then delete the old field. And make each half ABORT
on the assumption it depends on — a duplicate id, a record not yet copied —
rather than guessing. Fire both aborts deliberately against the emulator; an
abort path you have never seen run is not a safety net.

### `localeCompare` still sorts emoji-prefixed names by the emoji
Switching a Firestore `orderBy` to a client-side `localeCompare` fixes code-unit
ordering but not this: a name like `📋 Governance` still files under the emoji, so
every emoji-prefixed entry clusters at one end of the list instead of under the
word a reader is looking for. Strip leading non-alphanumerics for the sort key:

```ts
const sortKey = (name: string) => name.replace(/^[^\p{L}\p{N}]+/u, '') || name;
```

Verify it by LOOKING at the rendered list — the ordering was wrong in exactly the
way the code comment claimed it had fixed.

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

### A filled field empties itself, and the error blames the BUTTON
Playwright `fill()`s a text field, then clicks the submit button, and the click
times out 30s later reporting that the button is disabled. The button looks
broken. It is not: the FIELD is empty by the time the click is attempted, and
the button is gated on the text.

These are controlled React inputs. `fill()` sets the DOM value and dispatches an
input event, but a Firestore snapshot landing in the same tick makes React
re-render from state that has not caught up, and the field reverts to empty. It
bites hardest in seeding/automation loops, where the PREVIOUS write's snapshot
arrives while you are filling the next value — so the first item succeeds and
the second hangs, which looks like the form breaking after one use.

**Checking the value right after filling is not enough.** That check passes; the
wipe happens after it. Retry the whole fill-then-act cycle instead:

```js
async function fillThen(page, placeholder, value, act) {
  for (let attempt = 1; attempt <= 6; attempt += 1) {
    await page.getByPlaceholder(placeholder).fill(value);
    try { await act({ timeout: 4000 }); return; }   // short timeout is the point
    catch { await page.waitForTimeout(500); }        // wiped, or still busy — refill
  }
  throw new Error(`${placeholder} kept being cleared`);
}
```

The short per-attempt timeout is what converts a 30-second dead wait into a
retry. And apply it to EVERY controlled input in the script, not just the one
that failed — the others are the same gun, unfired.

### The screen underneath is still in the DOM, so `.first()`/`.last()` lie
A native-stack navigator on react-native-web keeps the screen you navigated away
from **mounted**, hidden with `display: none`. Its text, its test ids and its
fields are all still queryable. So a positional text locator can resolve to the
screen *underneath* the one on screen — and because that element will never
become visible, Playwright retries against it until the timeout and the run dies
at a step that has nothing wrong with it.

It bites hardest where the same label exists on both screens (a picker field, a
name, a status word), and it is timing-dependent: the wrong element wins only in
the window between the tap and the pushed screen mounting, so the suite fails
intermittently and the failing step looks arbitrary. Two sibling apps were each
losing roughly one run in two to this before it was named.

The locator strategies are **not** equivalent here:

| | sees hidden nodes? |
|---|---|
| `getByText` / `getByLabel` / CSS `locator()` | **yes** |
| `getByTestId` | **yes** — it is a plain attribute selector, despite feeling "precise" |
| `getByRole` | no — role engines skip `display:none`, as a screen reader does |

So "use a test id instead of text" is not the fix, and documenting it as one is
worse than saying nothing. The fix is to filter first, or to navigate by role:

```js
const firstOnScreen = (l) => l.filter({ visible: true }).first();
const lastOnScreen  = (l) => l.filter({ visible: true }).last();
await lastOnScreen(page.getByText('Pick an activity')).click();
```

Make it a **property of the file**, not a patch at the two call sites that
happened to bite: a bare `.first()`/`.last()` on a text or test-id locator
anywhere in a navigation-driving suite is the same bug waiting for a different
day. A harness that navigates purely by role never meets this at all.

### A squashed `<input type="date">` reports no overflow at all
The natural way to ask "is this control narrower than its content" is
`scrollWidth > clientWidth`. On a date or time input that is **always false**,
however badly it is crushed: Chromium draws the widget in a UA shadow root that
clips rather than scrolls, so the element reports a clean bill of health while
showing `08` where a date should be.

The trap is that the same signal *works* on `<select>` and on a text input — it
overflows by real pixels — which is exactly enough plausibility to survive review
and to make the date case look like "no problem here" rather than "no signal
here". Two harnesses on this stack wrote that check independently and both were
inert on the exact bug that motivated them; both were caught only by squashing a
field on purpose and watching the suite stay green.

Ask the control what it would take **naturally**: clone it out of the flex row,
let it size to its content, measure, discard. No threshold, no per-type special
case, and it answers for every control kind.

```js
const clone = el.cloneNode(false);
Object.assign(clone.style, {
  position: 'absolute', visibility: 'hidden',
  width: 'auto', maxWidth: 'none', flex: 'none',
});
document.body.appendChild(clone);
const natural = clone.getBoundingClientRect().width;
clone.remove();
if (natural - el.getBoundingClientRect().width > 2) { /* squashed */ }
```

Measured on a date field squashed by a `flex: 1` wrapper (flexBasis 0) sitting
beside two non-shrinking buttons — the shape that causes this in the first place:

| | `scrollWidth - clientWidth` | min-content shortfall |
|---|---|---|
| healthy | 0 | 0 |
| squashed to 58px | **0** — blind | 85px |

Why it matters beyond the check: a field squashed this way **bleeds nothing and
overlaps nothing**, so a sweep's other geometry is all correct and all silent. It
is invisible to every structural check and visible instantly in a screenshot,
which is the combination that keeps it in a shipped app.

### The header Back is an `<a>`, so `getByRole('button')` never finds it
The entry above makes `getByRole` the safe engine. It has one trap of its own on
this stack: **the navigator's back control is not a button.**

`PlatformPressable` renders `role="link"` whenever it is given an `href`, and a
stack navigator gives it one as soon as the app has a `linking` config — which is
also what makes the browser's own Back work, so any web build worth testing has
it. The accessible name is `Go back` when there is no previous title, and
`<Previous title>, back` when there is.

A "can you leave this screen?" check written as
`getByRole('button', { name: /back/i })` therefore matches nothing, and reports
**every pushed screen in the app** as a dead end. That is a check failing on its
own selector rather than on the thing it is checking, and it is convincing:
dozens of failures, all naming real screens.

Query by label and let the role fall where it may:

```js
const back = (page) =>
  page.getByLabel(/(^|,\s*)(go\s+)?back$/i).filter({ visible: true }).first();
```

...and in an in-page evaluation, look at `[role="button"], [role="link"], button,
a[href]` rather than buttons alone.

Worth knowing beyond tests: it is a real link with a real `href`, so a
middle-click or "open in new tab" on your back arrow does something, and it is
keyboard-focusable as a link.

### A fire-and-forget write, then a navigation, reads back as "it did not persist"
A handler that calls `updateDoc(...)` without awaiting it returns immediately.
Navigate or reload in the next line and the page can be torn down with the write
still unsent — so the assertion after the reload sees the OLD value. That is
indistinguishable from the persistence bug the check exists to catch, and it
sends you looking at rules, listeners and the SDK's offline cache.

Wait for something the *round trip* changes before navigating. A control bound to
a snapshot listener rather than to local state is ideal: it flipping is proof the
write reached the server and came back.

```js
await toggle.click();
await page.waitForFunction(() => {
  const s = document.querySelectorAll('[role="switch"]');
  return s.length > 0 && s[s.length - 1].checked === false;   // listener-driven
}, undefined, { timeout: 15000 });
await page.goto(base);   // only now
```

### Two repos on one machine fight over the emulator ports
The Firebase emulator ports are fixed in `firebase.json` **and** compiled into the
client (`connectFirestoreEmulator(host, 8080)`), and the usual "free the ports
first" helper kills by port. So two checkouts on the same machine cannot run
their suites at once: whichever starts second SIGTERMs the other's Firestore
emulator. The victim sees `Firestore Emulator has exited with code: 143` if it is
lucky, and if it is not, an inexplicable mid-run timeout or a silently lost
write — which reads exactly like a bug in the code under test.

**Find the owner before you kill anything.** `ps` is not enough — two checkouts
can share a `--project` value, and a truncated `ps` line is a classic way to kill
the wrong emulator. The port's own process is authoritative:

```sh
pid=$(ss -lptn "sport = :$PORT" | grep -oP 'pid=\K[0-9]+' | head -1)
readlink /proc/$pid/cwd        # the checkout that owns it
```

Use `ss`, not `lsof`: `lsof` is often absent from a non-interactive shell, and a
missing `lsof` turns a port guard into a no-op that always reports "free".

**The fix is a port block per checkout.** Give each repo a base and keep fixed
offsets, so a port number names its owner at a glance:

| offset | service | | offset | service |
|---|---|---|---|---|
| +0 | firestore | | +5 | hub |
| +1 | firestore `websocketPort` | | +6 | logging |
| +2 | auth | | +7 | storage |
| +3 | functions | | +10 | web dev server |
| +4 | ui | | +11 | second web dev server |

Choose bases **above the ephemeral range** (`/proc/sys/net/ipv4/ip_local_port_range`,
commonly 32768–60999) and clear of Firebase's own defaults, which top out at
**9499** (`firebase-tools/lib/emulator/constants.js`). A base of 61000, 61100,
61200… satisfies both, so nothing is ever handed out at random onto your block.

Four details decide whether this actually works:

- **`firestore.websocketPort` is a NESTED key that defaults to 9150 and is not
  derived from `firestore.port`.** Move `firestore.port` alone and every checkout
  still shares 9150. Worse, left unset it *silently increments* on collision
  instead of erroring — `controller.js` sets `portFixed: !!wsPortConfig`.
- **`ui`, `hub`, `logging`, `eventarc` and `tasks` have
  `FIND_AVAILBLE_PORT_BY_DEFAULT: true`** and drift silently; `firestore`, `auth`,
  `functions` and `storage` hard-fail. Pin the drifters too — turning silent
  drift into a hard error is the point.
- **The client's port must be a SOURCE LITERAL, never `EXPO_PUBLIC_*`.** On a
  native debug build those come from the environment that started *Metro*, and
  one Metro can serve several projects — the app's backend address would become a
  property of an unrelated process's environment. Env-with-default is worse
  still: it fails *toward* the collision, since an unset or mistyped var falls
  back to the shared default and connects to the neighbour, which reads and
  writes happily and passes.
- **The kill helper must sweep only its own block.** A sweep that reaches past it
  is precisely what kills a sibling's emulator.

**Land a consistency test before you move anything.** The ports cannot live in
one file — `firebase.json`, the client, the scripts and the shell sweeps each
need their own representation. So assert that they agree, and that every value
is inside the block. Landed first it passes on the old ports; then the move and
the range assertion go in together, and every half-migrated state fails in
seconds instead of surfacing later as a suite that quietly passed against the
neighbour's database.

**Enumerate the consumers by grepping for the OLD numbers, not by listing the
ones you know about**, and add the abandoned ports to the test as a
never-again list. The consumer most likely to be missed is `package.json` — a
dev-server port lives there as `--port 8086` inside a script string, in a file
nobody thinks of as configuration and which a `scripts/`-only scan does not
open. Miss it and the documented dev loop cannot complete at all: the runner
waits on the new port, the server answers on the old one, the seed fetches the
new one, and the sweep list does not free the old one, so a stray server is left
behind on every attempt. Match `--port N` as well as `host:port`; a bare number
cries wolf, because 4000 and 8000 are also millisecond timeouts.

### Your geometric checks are unanchored: assert the viewport actually applied
A layout sweep measures the DOM against the DOM — this element against that one,
this column against the scroller that holds it. That makes every check internally
consistent and completely **silent about which width it ran at**. The width came
from a Playwright viewport option and was believed.

Nothing in such a file can tell you the option applied. If one silently did not,
every check still passes, every screenshot is mislabelled, and "N checks across
five widths" becomes a sentence about nothing. It is the *a tour that cannot fail
is a screenshot generator* rule one level up — at the tour's premise rather than
at its steps, which is where nobody thinks to look.

Two independently written harnesses, different codebases, different assertion
sets, both sabotaged the same way (viewport set to `w - 40` while still claiming
`w`):

| | result at the wrong width |
|---|---|
| harness A | **124 of 127 checks passed** — the only 3 failures were the new premise check |
| harness B | 55 of 64 — 4 premise checks, plus 5 genuine failures from a check that happens to be sensitive to *absolute* width |

The agreeing half is the finding: in both, **every anchoring-dependent check
passed** — bleed, overlap, right-edge clipping, escape routes, breakpoint layout.
Not one could tell. B's extra five are worth naming precisely so they are not
mistaken for coverage: a "control narrower than its content" check fired because
280px is below anything that app was designed for. That is luck of sabotage size
— it would not have fired at 5px — not a substitute for the check.

Assert it directly, once per **context** and before the tour:

```js
const at = await page.evaluate(() => ({
  layout: document.documentElement.clientWidth,   // the layout box, not innerWidth
  window: window.innerWidth,
}));
check(`${tag} laid out at ${width}px`, at.layout === width,
      `clientWidth = ${at.layout}, innerWidth = ${at.window}`);
```

Per context, not per width: each browser context carries its own `viewport`
option, so checking one says nothing about the next. Per context and not per
screen either — one honest line per context beats a screenful of noisy ones. And
**before** the tour, so a bad viewport fails ahead of the geometry rather than
after a screen of it has been measured against the wrong reference.

Watch for a dead reference width while you are in there. If the sweep threads a
`width` argument down to assertions that have stopped using it, `no-unused-vars`
will not save you: it defaults to `args: 'after-used'`, so a parameter followed by
used ones is never reported. In the two harnesses above the same dead argument was
invisible in one and caught in the other, decided by nothing but its position in
the signature. `args: 'all'` with `argsIgnorePattern: '^_'` is the setting that
sees it — measure the violation count before adopting, it differs sharply between
codebases.

### Confirmation dialogs silently do nothing under Playwright
Playwright **auto-dismisses** `window.confirm`. Register the handler, and assert
on the text so the test proves a confirmation was demanded:

```js
page.on('dialog', async (d) => { lastConfirm.set(page, d.message()); await d.accept(); });
```

### `assertFails` passes for the wrong reason
A rules test that only asserts a write is denied proves nothing about *why*. Add a
field the validator rejects, or a typo in a doc id, and it still passes — green
forever, testing nothing. Auditing a mature suite, several "the lock blocks this"
tests turned out to be failing on malformed fixtures instead.

Pair every `assertFails` with a **positive control**: the same write, succeeding
once the condition under test is removed.

```js
await assertFails(update(asOwner, entryRef, change));   // blocked by the lock…
await removeTheLock();
await assertSucceeds(update(asOwner, entryRef, change)); // …and only by the lock
```

The same applies to fixtures. A constant like `T0 = 1752570000000` paired with a
hand-written `'2026-07-15'` day key is unverifiable by eye — and was a year off.
Derive fixtures (`Date.UTC(2026, 6, 15, 9)`) so they cannot drift from the labels
they carry.

## Rules protect clients — not your own backend

Security rules apply to client SDKs. The Admin SDK **bypasses them entirely**, so
every invariant expressed only in rules is unenforced for your own scheduled jobs,
triggers, and callables. This is easy to forget precisely because the rule looks
authoritative when you read it.

The dangerous shape is an immutability lock: "once approved, nobody may modify
this period's records." Clients obey. Then a nightly cleanup job edits one of
those records, and the frozen thing changes with no trace and no error.

When a backend job writes to data that rules protect:

- **Re-check the invariant in the job.** The rule is not a shared guarantee.
- **Decide deliberately between skipping and proceeding.** Skipping can be worse —
  leaving a session open forever means retrying every hour, permanently.
- **If you proceed, repair derived state and tell a human.** A sealed record
  changing after the fact is exactly what nobody will notice on their own; a
  Sentry message costs nothing and is the only reason anyone will ever know.

Corollary worth probing: rules often permit a state your *client* prevents. If the
UI blocks submitting while a session is still running, verify the rules do too, or
that state will arrive eventually through a retry, a stale tab, or another client.

### A `get` on an ABSENT document is refused, not answered "no"
`resource` is **null** for a document that does not exist, so any rule arm that
dereferences `resource.data` is an evaluation *error* on that read — and an
evaluation error is a denial. The client cannot tell it apart from "you may not
see this": both arrive as `permission-denied`.

That matters because *asking about an absent document is often the normal case*.
"Is this user a member of this group?" against `memberships/{userId}_{groupId}`
is a yes/no question whose answer is usually no — and every "no" comes back as a
permission denial, one per row, on a screen that is working exactly as intended.

```
// denies for a non-member — resource is null, so resource.data throws
allow get: if request.auth.uid in
  get(/databases/$(db)/documents/groups/$(resource.data.groupId)).data.ownerUids;
```

**Ask it as a constrained list instead.** A list never evaluates against a null
resource — an absent document simply is not in the result set:

```ts
query(collection(db, 'memberships'),
      where('groupId', '==', groupId), where('userId', '==', userId))
```

The `groupId` equality is what keeps the rule affordable (every returned row
resolves the *same* parent `get()`, one document-access call however large the
group), and the second equality keeps the answer to one row. Equality-only
filters need no composite index.

The alternative — allowing the missing-document read with `resource == null` —
is right only when there is nothing there to leak. It suits a self-keyed row the
caller is about to create (`progress/{uid}_{itemId}`: no document, and the id is
one they already know). It is wrong wherever **existence is itself the private
fact**, because then the denial *is* the answer: whoever can read the absent ones
can probe any pair and read "denied" as yes.

Two things make this expensive to find. It fails **loudly but harmlessly** — the
screen renders correctly, because "refused" and "absent" both mean the row draws
nothing — so it shows up only as an error banner and a stream of Sentry events
from a feature nobody has reported. And an outcome-based end-to-end assertion
("the empty state appears") passes either way; the assertion that catches it is
the **absence of the error surface**, not the presence of the right text.

### Claims changes do not evict a live session
`setCustomUserClaims` updates the token *next time one is minted*. An ID token
already in hand stays valid for up to an hour, and rules trust that token — so
disabling someone does not necessarily stop them.

Three layers, and you want all three:

1. **A stamp the client watches** (e.g. `claimsUpdatedAt` on the user doc) so a
   connected client force-refreshes within a second.
2. **`revokeRefreshTokens(uid)`** on any loss of access, so a backgrounded or
   offline client cannot mint a fresh token from an old refresh token.
3. **Accept the residual**: an unexpired ID token still works, and Firestore rules
   cannot check revocation time. Write that limitation down rather than implying
   the eviction is instant.

### A local-date key can be bounded even though rules can't do timezone math
Bucketing by a client-computed local date (`dayKey`) is standard, and rules have no
IANA database to verify it against the instant. That does not make it a pure trust
boundary: every real UTC offset lies in **[-12h, +14h]**, so the instant behind
local day D must fall in **[D_utc − 14h, D_utc + 36h)**.

```
function dayKeyPlausible(dayKey, start) {
  let p = dayKey.split('-');
  let dayMs = timestamp.date(int(p[0]), int(p[1]), int(p[2])).toMillis();
  return start >= dayMs - 14 * 3600000 && start < dayMs + 36 * 3600000;
}
```

Loose on purpose — it will not catch a DST hour, but it catches a record filed
days from when it happened, which is what moves data into the wrong reporting
bucket or past a period lock. No honest client can trip it.

### Deleting a doc as a state transition destroys the audit trail
"Withdraw" and "reopen" are tempting to model as deleting the doc: absence is a
clean representation of "back to draft", and it keeps the state machine small. The
cost is invisible until someone asks who approved something and when — the record
was in the doc you deleted.

Keep the delete (the state model really is simpler) and add an **append-only log
written by a document trigger** — `onDocumentWritten` fires on deletes, with the
final state in `before`. Write it server-side: a client that could write the log
could forge or omit the events it exists to preserve, so rules deny all access.

One caveat to design around: **triggers don't report who issued the write.** For
deletes you often must infer the actor from the state it was deleted *from* (only
an admin can delete an approved record), or record `null` honestly rather than
guessing.

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

### "It's slow" may be "my input was thrown away"
A discarded tap and a slow handler are indistinguishable from the outside: both
are a control you touched and a screen that did not change. Users report the
second because it is the one they have words for, and a profiler then confirms
some real-but-irrelevant cost and you optimise the wrong thing.

**Before optimising anything a person called slow, establish that the handler
ran at all.** A screen recording settles it in a minute: find the frame the
touch lands, then check whether the control ever entered its pressed state —
measure the fill colour, do not eyeball it. No press state means no handler, and
no amount of profiling the handler will help.

### A guard you have not falsified is not a guard
A lint rule, a schema check, a CI assertion — each can be present, well
commented, and inert. The failure mode is quiet: `no-restricted-syntax` is one
rule *name*, and ESLint flat config **replaces** a rule rather than merging it,
so a second config block covering the same files silently disables the first.
Both rules read correctly in the file. The run is green. Neither is enforcing.

The same applies to a suite nobody invokes, an assertion inside a branch never
taken, and a check whose subject cannot reach it.

**Introduce one violation of each rule you just wrote, watch it fail, revert.**
A green run is evidence only after you have seen the red one. When two guards
share a mechanism, falsify them *separately* — passing is not proof that both
are live, only that at least one is.

### Web is not evidence about native, and an emulator is not a device
`react-native-web` resolves flexbox trees differently, so a screen that renders
perfectly in a browser can be blank on a phone. An emulator misreports IME
insets, so keyboard behaviour differs from real hardware.

**Reproduce on the surface that is broken.** A green web suite says nothing about
a native layout bug — the divergence *is* the bug.

The gap is not only layout. Anything the OS owns — a permission prompt, where it
lands, what happens when the person leaves for the settings app and comes back —
has no browser equivalent at all, so a suite cannot be wrong about it; it simply
never had an opinion. A feature can be reviewed twice, tested on both surfaces
and shipped, with its central interaction never once having run. Say plainly
which platform a claim rests on, and treat "never run on a device" as an open
item rather than a formality.

Watch for the closed loop when you do run it: a screen that gives correct advice,
sends the person out of the app to act on it, and cannot see that they did. Every
individual piece is right and the feature is unusable, and no assertion about the
screen catches it, because at the moment the assertion runs the screen is telling
the truth.

### The APK at the output path may be the PREVIOUS build
`assembleRelease` writes to a fixed path, and the file from last night's build is
sitting there before the new one starts. A publish script pointed at that path
will happily upload it — so a release can go out labelled vNEXT carrying vPREV's
bytes, and nothing anywhere disagrees.

Gradle's own progress output does not help: it prints tasks for minutes before it
replaces the artefact.

**Check the mtime against the clock, not the file's existence**, and confirm the
version baked into the binary before publishing — the readable `versionName`
survives in the binary `AndroidManifest.xml` string pool, so a few lines of
Python prove which release the bytes are. Then check the uploaded asset's byte
size equals the local file's. A rolling-tag asset looks identical before and
after a publish; size and timestamp are the only evidence it moved.

### A build tool can succeed loudly on the WRONG target
`** ARCHIVE SUCCEEDED **` is not evidence that your app was archived. The scheme,
target and product are all inputs *you* supplied — ask a build system for a
static library and it will build one, perfectly, and congratulate you. The
resulting archive contained no app at all, and the only complaint arrived one
step later, from a different tool, about a plist key.

The general shape: **a success message is scoped to what the tool was asked to
do, never to what you meant.** Wherever a step names the thing it will act on — a
scheme, target, variant, flavour, project — echo that name in the log and assert
it is the one you expect, in the same breath as asserting the output exists.
`[ -d "$ARCHIVE" ]` passed happily. `[ -d "$ARCHIVE/Products/Applications" ]` is
the check that carried meaning. Existence checks on an output path are the
weakest possible assertion: prefer one that would fail if the *content* were
wrong.

### A test hook on a `.web.tsx` seam covers ONE layout, silently
A platform seam (`Foo.tsx` / `Foo.web.tsx`) is two files. A `testID` — or a raw
`data-testid` on the web file, which is easy to reach for because that file
already emits real DOM — exists on that layout and no other. Every e2e suite
addressing it then runs at whatever viewport makes that layout render, and the
other layouts have **no coverage at all** while the suites report green.

The symptom is not a failure. It is a suite that has been passing for months and
a `locator ... Timeout 30000ms` the first time anything drives the other layout.

**Put the handle on every seam, or on the shared component they all embed.** Then
check what viewport your suites actually run at: if they all straddle one side of
the breakpoint, the phone-first layout is untested no matter how many checks pass.

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

### For RULES specifically, you can read the deployed source back
Probing the behaviour is the general remedy above, but a rules deploy resists it:
evaluating a rule needs an identity, and on production the only identities are
real people. Impersonating one to test a deploy writes as them.

Rules are the one resource whose deployed *source* is readable. Fetch the current
release, then the ruleset it names, and diff the content against the file you
meant to deploy:

```
GET https://firebaserules.googleapis.com/v1/projects/$P/releases/cloud.firestore
GET https://firebaserules.googleapis.com/v1/$RULESET_NAME
```

`.source.files[0].content` is the text. With user ADC you need an
`x-goog-user-project: $P` header or the call fails 403 asking for a quota
project — an error that reads like a missing permission and is not one.

Byte-identical source plus a green suite against those same bytes is a complete
proof: rules evaluation is deterministic given source, token and document, so
identical source cannot behave differently. It is stronger than one hand-typed
check through the UI, which exercises a single path and writes real data. Use the
diff as the gate and keep the hand check as a sanity pass, not the other way
round.

The same endpoint answers "which ruleset is *actually* live" when a deploy
succeeded from the wrong directory or the wrong project alias — the case where
every message you saw was green.

### Say what you did not verify
Several bugs here were reported fixed on the strength of a plausible mechanism.
The cost is not the wrong fix; it is that the next person trusts it. When the
architecture is right but the symptom is unconfirmed, **write that down** — in
the commit message, in the notes, to the user. An honest known-gap is cheaper
than a false all-clear.
