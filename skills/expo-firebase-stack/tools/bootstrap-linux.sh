#!/usr/bin/env bash
#
# Bootstrap a full Expo + react-native-web + Firebase toolchain on a fresh
# Debian/Ubuntu x86_64 box, entirely under $HOME. No root, no sudo.
#
# The point of this script is that a new machine is a 15-minute command rather
# than forty ad-hoc ones. It is idempotent: everything already present is
# detected and skipped, so re-running it is how you upgrade or repair.
#
#   ./bootstrap-linux.sh                          # everything
#   ./bootstrap-linux.sh --skip-android           # web/functions only (~1 GB)
#   ./bootstrap-linux.sh --repo ~/src/my-app      # also npm ci + Playwright there
#   ./bootstrap-linux.sh --jdk21-aliases APP,LIB   # export APP_JDK21_HOME etc.
#   ./bootstrap-linux.sh --self-test              # verify, install nothing
#
# WHY NO ROOT. Two discoveries make it unnecessary, and both are load-bearing:
#
#   * `apt-get download` and `dpkg-deb -x` work unprivileged. So the ~90 Debian
#     libraries Chromium and the Android emulator link against can be unpacked
#     into $PREFIX/syslibs and found through LD_LIBRARY_PATH. Without this you
#     are blocked on a root shell before a single Playwright test can run.
#   * npm's global prefix can be moved to ~/.local, so `npm i -g` works.
#
# WHAT STILL NEEDS ROOT, and it is almost nothing:
#
#   * /usr/bin/google-chrome, IF some script of yours hardcodes that absolute
#     path. A shim is installed at ~/.local/bin/google-chrome, which covers
#     everything that calls `google-chrome` by name.
#   * Nothing else. See check-host.sh for the one thing root cannot fix either.
#
set -uo pipefail

# ---------------------------------------------------------------- settings --
PREFIX="${EFS_PREFIX:-$HOME/opt}"
BINDIR="$HOME/.local/bin"
ENV_FILE="${EFS_ENV_FILE:-$HOME/.expo-firebase-stack-env.sh}"
WORK="${EFS_WORK:-$HOME/.cache/efs-bootstrap}"

NODE_MAJOR=22
# Expo 57 / RN 0.86 defaults, read out of
# expo-modules-autolinking/.../ExpoRootProjectPlugin.kt rather than guessed.
# Bump these deliberately when the Expo major changes, and say so in a commit.
ANDROID_BUILD_TOOLS="35.0.0"
ANDROID_PLATFORMS="35 36"
ANDROID_NDK="27.1.12297006"
ANDROID_CMAKE="3.22.1"
ANDROID_IMAGE_API="35"
FIREBASE_TOOLS="firebase-tools@^15"
AVD_NAME="tb_emu"

SKIP_ANDROID=false
SKIP_AVD=false
SELF_TEST_ONLY=false
JDK21_ALIASES=""
REPOS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)         PREFIX="$2"; shift 2 ;;
    --jdk21-aliases)  JDK21_ALIASES="$2"; shift 2 ;;
    --repo)           REPOS+=("$2"); shift 2 ;;
    --avd-name)       AVD_NAME="$2"; shift 2 ;;
    --skip-android)   SKIP_ANDROID=true; shift ;;
    --skip-avd)       SKIP_AVD=true; shift ;;
    --self-test)      SELF_TEST_ONLY=true; shift ;;
    -h|--help)        sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

JDK17="$PREFIX/jdk-17"
JDK21="$PREFIX/jdk-21"
SDK="$PREFIX/Android/Sdk"
GCLOUD="$PREFIX/google-cloud-sdk"
SYSLIBS="$PREFIX/syslibs"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    \033[33m! %s\033[0m\n' "$*" >&2; }
die()  { printf '\n\033[31mFAILED: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight --
preflight() {
  say "Preflight"
  [ "$(uname -m)" = "x86_64" ] || die "x86_64 only; this is $(uname -m)"
  command -v curl    >/dev/null || die "curl is required"
  command -v tar     >/dev/null || die "tar is required"
  command -v python3 >/dev/null || die "python3 is required"
  command -v dpkg-deb >/dev/null || warn "dpkg-deb missing — system-library staging will be skipped"

  # tar cannot decompress .tar.xz without the xz binary, which minimal images
  # often lack. python3's lzma module is the fallback, so xz is not required.
  if ! command -v xz >/dev/null; then
    python3 -c 'import lzma' 2>/dev/null \
      || die "neither the xz binary nor python3's lzma module is available"
    info "xz missing; will decompress .tar.xz through python3 lzma"
  fi

  local avail
  avail=$(df -Pk "$HOME" | awk 'NR==2{print int($4/1024/1024)}')
  info "free space in \$HOME: ${avail} GiB"
  if [ "$SKIP_ANDROID" = false ] && [ "$avail" -lt 20 ]; then
    die "need ~20 GiB free for the Android SDK (have ${avail} GiB); use --skip-android"
  fi
  mkdir -p "$PREFIX" "$BINDIR" "$WORK" || die "cannot write to $PREFIX"
  info "install prefix: $PREFIX"
}

# Extract a tarball whatever its compression, without needing xz.
untar_to() { # untar_to <archive> <dest-dir>
  local archive="$1" dest="$2"
  mkdir -p "$dest"
  case "$archive" in
    *.tar.xz)
      if command -v xz >/dev/null; then
        tar -xJf "$archive" -C "$dest" --strip-components=1
      else
        python3 -c "import lzma,shutil,sys;shutil.copyfileobj(lzma.open(sys.argv[1]),open(sys.argv[2],'wb'))" \
          "$archive" "$archive.plain" || return 1
        tar -xf "$archive.plain" -C "$dest" --strip-components=1
        rm -f "$archive.plain"
      fi ;;
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$dest" --strip-components=1 ;;
    *.zip)
      # unzip is frequently absent; python3's zipfile always is not.
      python3 -c "import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
        "$archive" "$dest" ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------------- node --
install_node() {
  say "Node ${NODE_MAJOR}"
  if [ -x "$PREFIX/node/bin/node" ]; then
    info "already present: $("$PREFIX/node/bin/node" -v)"
    return 0
  fi
  local ver
  ver=$(curl -sSL https://nodejs.org/dist/index.json \
    | python3 -c "import json,sys;print(next(r['version'] for r in json.load(sys.stdin) if r['version'].startswith('v${NODE_MAJOR}.')))") \
    || die "could not resolve the latest Node ${NODE_MAJOR}"
  info "installing $ver"
  curl -sSL -o "$WORK/node.tar.xz" "https://nodejs.org/dist/$ver/node-$ver-linux-x64.tar.xz" || die "node download failed"
  untar_to "$WORK/node.tar.xz" "$PREFIX/node-${NODE_MAJOR}" || die "node extract failed"
  ln -sfn "$PREFIX/node-${NODE_MAJOR}" "$PREFIX/node"
  rm -f "$WORK/node.tar.xz"
  info "installed $("$PREFIX/node/bin/node" -v)"
}

# ------------------------------------------------------------------- java --
install_jdk() { # install_jdk <major> <dest>
  local major="$1" dest="$2"
  if [ -x "$dest/bin/java" ]; then
    info "JDK $major already present"
    return 0
  fi
  info "installing Temurin JDK $major"
  curl -sSL -o "$WORK/jdk$major.tar.gz" \
    "https://api.adoptium.net/v3/binary/latest/$major/ga/linux/x64/jdk/hotspot/normal/eclipse" \
    || die "JDK $major download failed"
  untar_to "$WORK/jdk$major.tar.gz" "$dest" || die "JDK $major extract failed"
  rm -f "$WORK/jdk$major.tar.gz"
}

install_java() {
  # TWO JDKs, deliberately. The Android Gradle Plugin targets 17; the Firebase
  # emulators (Firestore/Auth/Storage are Java) need 21+. Making 17 the default
  # `java` and pointing a variable at 21 lets both work with no switching.
  say "Java (17 for Gradle, 21 for the Firebase emulators)"
  install_jdk 17 "$JDK17"
  install_jdk 21 "$JDK21"
  info "17: $("$JDK17/bin/java" -version 2>&1 | head -1)"
  info "21: $("$JDK21/bin/java" -version 2>&1 | head -1)"
}

# ---------------------------------------------------------------- android --
install_android() {
  say "Android SDK"
  export ANDROID_HOME="$SDK" ANDROID_SDK_ROOT="$SDK"
  export JAVA_HOME="$JDK17"
  export PATH="$JDK17/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$SDK/emulator:$PATH"

  # ANDROID_AVD_HOME is set EXPLICITLY because the JVM does not read $HOME:
  # `user.home` comes from the passwd entry, so avdmanager happily reads and
  # writes the real home even when HOME points somewhere else. Without this,
  # anything that runs the SDK under an overridden HOME — a container, CI, a
  # sandboxed test of this very script — silently touches the wrong directory
  # and reports an AVD that "already exists" somewhere you are not looking.
  export ANDROID_AVD_HOME="$HOME/.android/avd"
  mkdir -p "$ANDROID_AVD_HOME"

  if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
    info "installing command-line tools"
    curl -sSL -o "$WORK/cmdline-tools.zip" \
      "https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip" \
      || die "cmdline-tools download failed"
    rm -rf "$SDK/cmdline-tools/_x"
    untar_to "$WORK/cmdline-tools.zip" "$SDK/cmdline-tools/_x" || die "cmdline-tools extract failed"
    mkdir -p "$SDK/cmdline-tools"
    rm -rf "$SDK/cmdline-tools/latest"
    mv "$SDK/cmdline-tools/_x/cmdline-tools" "$SDK/cmdline-tools/latest"
    rmdir "$SDK/cmdline-tools/_x" 2>/dev/null || true
    chmod +x "$SDK/cmdline-tools/latest/bin/"* 2>/dev/null || true
    rm -f "$WORK/cmdline-tools.zip"
  else
    info "command-line tools already present"
  fi

  yes 2>/dev/null | sdkmanager --licenses >/dev/null 2>&1 || true

  local pkgs=(platform-tools emulator "build-tools;$ANDROID_BUILD_TOOLS"
              "ndk;$ANDROID_NDK" "cmake;$ANDROID_CMAKE"
              "system-images;android-$ANDROID_IMAGE_API;google_apis;x86_64")
  local p
  for p in $ANDROID_PLATFORMS; do pkgs+=("platforms;android-$p"); done

  info "installing: ${pkgs[*]}"
  sdkmanager --install "${pkgs[@]}" >"$WORK/sdkmanager.log" 2>&1 \
    || { tail -20 "$WORK/sdkmanager.log" >&2; die "sdkmanager failed (see $WORK/sdkmanager.log)"; }
  info "SDK packages installed"

  if [ "$SKIP_AVD" = true ]; then
    info "skipping AVD (--skip-avd)"
    return 0
  fi
  if avdmanager list avd 2>/dev/null | grep -q "Name: $AVD_NAME"; then
    info "AVD $AVD_NAME already exists"
    return 0
  fi
  info "creating AVD $AVD_NAME (Pixel 6, API $ANDROID_IMAGE_API)"
  echo "no" | avdmanager create avd -n "$AVD_NAME" \
    -k "system-images;android-$ANDROID_IMAGE_API;google_apis;x86_64" \
    -d pixel_6 --force >/dev/null 2>&1 || { warn "AVD creation failed"; return 0; }
  local cfg="$HOME/.android/avd/$AVD_NAME.avd/config.ini"
  if [ -f "$cfg" ]; then
    sed -i 's/^hw.lcd.width=.*/hw.lcd.width=1080/;s/^hw.lcd.height=.*/hw.lcd.height=2400/' "$cfg"
    grep -q '^hw.ramSize'             "$cfg" && sed -i 's/^hw.ramSize=.*/hw.ramSize=3072/' "$cfg" || echo "hw.ramSize=3072" >>"$cfg"
    grep -q '^disk.dataPartition.size' "$cfg" && sed -i 's/^disk.dataPartition.size=.*/disk.dataPartition.size=6G/' "$cfg" || echo "disk.dataPartition.size=6G" >>"$cfg"
  fi
}

# ----------------------------------------------------------------- gcloud --
install_gcloud() {
  say "Google Cloud SDK"
  if [ -x "$GCLOUD/bin/gcloud" ]; then
    info "already present: $("$GCLOUD/bin/gcloud" --version 2>/dev/null | head -1)"
    return 0
  fi
  curl -sSL -o "$WORK/gcloud.tar.gz" \
    "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz" \
    || die "gcloud download failed"
  tar -xzf "$WORK/gcloud.tar.gz" -C "$PREFIX" || die "gcloud extract failed"
  rm -f "$WORK/gcloud.tar.gz"
  info "installed $("$GCLOUD/bin/gcloud" --version 2>/dev/null | head -1)"
}

# ------------------------------------------------------------- npm globals --
install_npm_globals() {
  say "npm globals (Firebase CLI, sentry-cli)"
  export PATH="$PREFIX/node/bin:$BINDIR:$PATH"
  # ~/.local, so `npm i -g` needs no root.
  npm config set prefix "$HOME/.local" >/dev/null 2>&1
  if command -v firebase >/dev/null && command -v sentry-cli >/dev/null; then
    info "already present: firebase $(firebase --version), $(sentry-cli --version)"
    return 0
  fi
  npm i -g "$FIREBASE_TOOLS" @sentry/cli >"$WORK/npm-global.log" 2>&1 \
    || { tail -20 "$WORK/npm-global.log" >&2; die "npm global install failed"; }
  info "firebase $(firebase --version 2>/dev/null), $(sentry-cli --version 2>/dev/null)"
}

# -------------------------------------------------------------- small bins --
install_small_tools() {
  say "jq, lsof, pip, python-markdown, Pillow"

  if ! [ -x "$BINDIR/jq" ] && ! command -v jq >/dev/null; then
    curl -sSL -o "$BINDIR/jq" \
      "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64" \
      && chmod +x "$BINDIR/jq" && info "jq installed" || warn "jq install failed"
  else
    info "jq present"
  fi

  # lsof matters more than it looks. Port-freeing helpers use `lsof -ti:PORT`;
  # when lsof is ABSENT that returns empty and the guard silently passes, so a
  # stale dev server keeps serving yesterday's bundle while the script reports
  # the port clear. A missing tool that turns a check into a no-op is worse
  # than a missing check.
  if ! command -v lsof >/dev/null && command -v dpkg-deb >/dev/null; then
    ( cd "$WORK" && apt-get download lsof >/dev/null 2>&1 \
      && dpkg-deb -x lsof_*.deb "$SYSLIBS" \
      && ln -sf "$SYSLIBS/usr/bin/lsof" "$BINDIR/lsof" ) \
      && info "lsof installed" || warn "lsof install failed — port guards will be no-ops"
  else
    info "lsof present"
  fi

  if ! python3 -m pip --version >/dev/null 2>&1; then
    curl -sSL -o "$WORK/get-pip.py" https://bootstrap.pypa.io/get-pip.py \
      && python3 "$WORK/get-pip.py" --user --break-system-packages -q >/dev/null 2>&1 \
      && info "pip installed" || warn "pip install failed"
  else
    info "pip present"
  fi
  # --break-system-packages is Debian 12+ (PEP 668). It only ever touches
  # ~/.local, so it cannot damage the system interpreter.
  python3 -m pip install --user --break-system-packages -q markdown Pillow >/dev/null 2>&1 \
    && info "markdown + Pillow installed" || warn "markdown/Pillow install failed"
}

# ------------------------------------------------- staged system libraries --
stage_syslibs() {
  say "System libraries for Chromium and the Android emulator (no root)"
  command -v dpkg-deb >/dev/null || { warn "dpkg-deb missing; skipping"; return 0; }
  command -v apt-get  >/dev/null || { warn "apt-get missing; skipping"; return 0; }

  # Ask Playwright for its own list where possible, so this does not drift as
  # Playwright versions change. The static list is the fallback.
  local pkgs=""
  if command -v npx >/dev/null; then
    pkgs=$(npx --yes playwright install-deps --dry-run chromium 2>/dev/null \
           | sed -n '2,200p' | sed 's/^ *//' | grep -v '^$' | tr '\n' ' ')
  fi
  if [ -z "${pkgs// /}" ]; then
    info "using the built-in library list"
    pkgs="libx11-xcb1 libdrm2 libice6 libsm6 libnspr4 libnss3 libpulse0 libxi6
      libxkbfile1 libtcmalloc-minimal4 libpcre2-16-0 libjpeg62-turbo
      libfontconfig1 libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64
      libcups2t64 libgbm1 libpango-1.0-0 libcairo2 libasound2t64 libxcomposite1
      libxdamage1 libxfixes3 libxrandr2 libxkbcommon0 libxrender1 libxshmfence1
      libgl1 libglx0 libvulkan1 libxcb-dri3-0 libxcb-glx0 libxcb-present0
      libxcb-randr0 libxcb-render0 libxcb-shm0 libxcb-sync1 libxcb-xfixes0
      libxxf86vm1 libwayland-server0 libgraphite2-3 libharfbuzz0b libthai0
      libdatrie1 libfribidi0 libpixman-1-0 libxt6t64 libxmu6 libxaw7 libxpm4
      libxfont2 libfontenc1 libunwind8 fonts-liberation fonts-dejavu-core
      libgl1-mesa-dri libglx-mesa0 mesa-libgallium"
  fi

  mkdir -p "$WORK/debs" "$SYSLIBS"
  ( cd "$WORK/debs" \
    && apt-get install --print-uris -y --no-install-recommends $pkgs 2>/dev/null \
       | grep "^'" | sed "s/^'\([^']*\)'.*/\1/" > uris.txt \
    && [ -s uris.txt ] \
    && xargs -P 8 -n 1 curl -sSL -O < uris.txt \
    && for d in *.deb; do dpkg-deb -x "$d" "$SYSLIBS"; done ) \
    || { warn "system-library staging failed; Chromium may not start"; return 0; }
  info "staged $(ls "$WORK/debs"/*.deb 2>/dev/null | wc -l) packages into $SYSLIBS"

  if [ -d "$SYSLIBS/usr/share/fonts" ]; then
    mkdir -p "$HOME/.config/fontconfig"
    cat >"$HOME/.config/fontconfig/fonts.conf" <<FC
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>$SYSLIBS/usr/share/fonts</dir>
  <cachedir>$HOME/.cache/fontconfig</cachedir>
</fontconfig>
FC
  fi
  rm -rf "$WORK/debs"
}

# ------------------------------------------------------------- environment --
write_env() {
  say "Environment file: $ENV_FILE"
  local aliases_block=""
  if [ -n "$JDK21_ALIASES" ]; then
    local a
    for a in ${JDK21_ALIASES//,/ }; do
      aliases_block="${aliases_block}export ${a}_JDK21_HOME=\"\$EFS_PREFIX/jdk-21\""$'\n'
    done
  fi

  cat >"$ENV_FILE" <<ENVEOF
# Expo + Firebase toolchain — generated by the expo-firebase-stack skill's
# bootstrap-linux.sh. Re-running the bootstrap regenerates this file.
#
# Sourced from BOTH ~/.profile and ~/.bashrc, and guarded against double
# sourcing. Both hooks are needed: Debian's stock .bashrc returns early when the
# shell is not interactive, so wiring it only there leaves every non-interactive
# script without a toolchain — the symptom is a bare "node: command not found"
# from something that works fine when you type it.
#
# A plain \`bash -c\` reads neither file. Scripts that need the toolchain outside
# a login shell should source this explicitly.

# NOT exported, deliberately. An exported guard is inherited by every child
# process, so the next login shell sees it set and returns before touching
# PATH — and \`bash -l\` has already reset PATH from /etc/profile by then. The
# symptom is "node: command not found" from any child shell while the parent
# works perfectly. Keep this a plain shell variable: it still prevents double
# sourcing within one shell, which is all it is for.
[ -n "\${EFS_ENV_LOADED:-}" ] && return 0 2>/dev/null
EFS_ENV_LOADED=1
export EFS_PREFIX="$PREFIX"

_efs_path() { case ":\$PATH:" in *":\$1:"*) ;; *) PATH="\$1:\$PATH" ;; esac; }

# npm's global prefix is ~/.local, so firebase/sentry-cli land in ~/.local/bin.
_efs_path "\$HOME/.local/bin"
_efs_path "\$EFS_PREFIX/node/bin"

# JDK 17 is the DEFAULT because the Android Gradle Plugin targets it. The
# Firebase emulators need 21+, which they find through the variables below
# without disturbing the Gradle default.
export JAVA_HOME="\$EFS_PREFIX/jdk-17"
_efs_path "\$JAVA_HOME/bin"
export JDK21_HOME="\$EFS_PREFIX/jdk-21"
${aliases_block}
export ANDROID_HOME="\$EFS_PREFIX/Android/Sdk"
export ANDROID_SDK_ROOT="\$ANDROID_HOME"
_efs_path "\$ANDROID_HOME/platform-tools"
_efs_path "\$ANDROID_HOME/emulator"
_efs_path "\$ANDROID_HOME/cmdline-tools/latest/bin"

[ -f "\$EFS_PREFIX/google-cloud-sdk/path.bash.inc" ] && . "\$EFS_PREFIX/google-cloud-sdk/path.bash.inc"

export PLAYWRIGHT_BROWSERS_PATH="\$HOME/.cache/ms-playwright"

# Debian libraries staged under \$EFS_PREFIX/syslibs by the bootstrap, because
# apt-get download and dpkg-deb need no root. Chromium and the Android emulator
# link against these; without them Chromium exits with
# "libnspr4.so: cannot open shared object file".
if [ -d "\$EFS_PREFIX/syslibs" ]; then
  export LD_LIBRARY_PATH="\$EFS_PREFIX/syslibs/usr/lib/x86_64-linux-gnu:\$EFS_PREFIX/syslibs/lib/x86_64-linux-gnu:\$EFS_PREFIX/syslibs/usr/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
  export XDG_DATA_DIRS="\$EFS_PREFIX/syslibs/usr/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
fi

unset -f _efs_path
export PATH
ENVEOF

  local hook="[ -f \"\$HOME/$(basename "$ENV_FILE")\" ] && . \"\$HOME/$(basename "$ENV_FILE")\""
  local f
  for f in "$HOME/.profile" "$HOME/.bashrc"; do
    [ -f "$f" ] || touch "$f"
    if ! grep -q "$(basename "$ENV_FILE")" "$f"; then
      printf '\n# --- Expo + Firebase toolchain (expo-firebase-stack skill) ---\n%s\n' "$hook" >>"$f"
      info "hooked into $(basename "$f")"
    else
      info "$(basename "$f") already hooked"
    fi
  done
}

# --------------------------------------------------------- chrome + browsers --
install_browsers() {
  say "Playwright Chromium + a google-chrome shim"
  # shellcheck disable=SC1090
  . "$ENV_FILE"

  # PLAYWRIGHT BROWSER BUILDS ARE PINNED TO THE PLAYWRIGHT PACKAGE VERSION.
  # `npx --yes playwright install chromium` pulls the LATEST playwright and
  # downloads ITS build — 1234, say — while a project pinned to 1.61.1 looks for
  # 1228 and reports "Executable doesn't exist at .../chromium_headless_shell-1228".
  # So the browsers that matter are installed per repo by install_repos(), using
  # each project's own pinned version. This standalone download exists only so
  # that a machine with no repos still has a Chromium for the shim below.
  if ! ls -d "$HOME/.cache/ms-playwright"/chromium-* >/dev/null 2>&1; then
    npx --yes playwright install chromium >"$WORK/playwright.log" 2>&1 \
      || warn "playwright browser download failed (see $WORK/playwright.log)"
    [ ${#REPOS[@]} -eq 0 ] && warn "browsers installed from the LATEST playwright; run 'npx playwright install chromium' inside each repo so the build matches its pinned version"
  else
    info "Playwright browsers already present"
  fi

  local chrome
  chrome=$(ls -d "$HOME/.cache/ms-playwright"/chromium-*/chrome-linux64/chrome 2>/dev/null | head -1)
  [ -z "$chrome" ] && chrome=$(ls -d "$HOME/.cache/ms-playwright"/chromium-*/chrome-linux/chrome 2>/dev/null | head -1)
  if [ -n "$chrome" ]; then
    # Some tooling (headless PDF printing in particular) shells out to a bare
    # `google-chrome`. This covers that without root. Anything that hardcodes
    # /usr/bin/google-chrome still needs a real install.
    cat >"$BINDIR/google-chrome" <<SHIM
#!/usr/bin/env bash
exec "$chrome" "\$@"
SHIM
    chmod +x "$BINDIR/google-chrome"
    info "google-chrome shim → $chrome"
  else
    warn "no Playwright Chromium found; google-chrome shim not created"
  fi
}

# ------------------------------------------------------------------ repos --
install_repos() {
  [ ${#REPOS[@]} -eq 0 ] && return 0
  say "Project repositories"
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  local r
  for r in "${REPOS[@]}"; do
    if [ ! -f "$r/package.json" ]; then warn "no package.json in $r — skipping"; continue; fi
    info "npm ci in $r"
    ( cd "$r" && npm ci >"$WORK/npm-ci.log" 2>&1 ) \
      || { tail -15 "$WORK/npm-ci.log" >&2; warn "npm ci failed in $r"; continue; }
    if [ -d "$r/node_modules/playwright" ]; then
      ( cd "$r" && npx playwright install chromium >/dev/null 2>&1 ) \
        && info "matched Playwright browsers for $r"
    fi
  done
}

# -------------------------------------------------------------- self-test --
self_test() {
  say "Self-test (a fresh login shell, which is what everything else gets)"
  local fails=0
  check() { # check <label> <command...>
    local label="$1"; shift
    local out rc
    # Capture status and output SEPARATELY. Piping into `tail` inside the `if`
    # made the pipeline's status tail's, not the command's, so anything that
    # failed while printing to stderr — "java: command not found" — was
    # reported as ok. A self-test that cannot fail is worse than none.
    out=$(bash -lc "$*" 2>&1); rc=$?
    out=$(printf '%s' "$out" | tail -1)
    if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
      printf '    \033[32mok\033[0m   %-22s %s\n' "$label" "$out"
    else
      printf '    \033[31mFAIL\033[0m %-22s %s\n' "$label" "${out:-no output}"
      fails=$((fails+1))
    fi
  }
  check node        'node -v'
  check npm         'npm -v'
  check "java (17)" 'java -version 2>&1 | head -1'
  check "java (21)" '"$JDK21_HOME/bin/java" -version 2>&1 | head -1'
  check firebase    'firebase --version'
  check gcloud      'gcloud --version 2>/dev/null | head -1'
  check sentry-cli  'sentry-cli --version'
  check jq          'jq --version'
  check lsof        'lsof -v 2>&1 | head -1'
  check markdown    'python3 -c "import markdown;print(markdown.__version__)"'
  if [ "$SKIP_ANDROID" = false ]; then
    check adb       'adb --version | sed -n 2p'
    check ndk       'ls "$ANDROID_HOME/ndk"'
    check avd       'emulator -list-avds | tr "\n" " "'
  fi

  # The one that actually matters, and the one a PATH check cannot fake:
  # launch Chromium. This is what the staged libraries are for.
  if [ -n "${REPOS[0]:-}" ] && [ -d "${REPOS[0]}/node_modules/playwright" ]; then
    if bash -lc "cd '${REPOS[0]}' && node -e 'import(\"playwright\").then(async p=>{const b=await p.chromium.launch();console.log(\"chromium \"+b.version());await b.close()})'" >/dev/null 2>&1; then
      printf '    \033[32mok\033[0m   %-22s launches\n' "chromium"
    else
      printf '    \033[31mFAIL\033[0m %-22s will not start — check LD_LIBRARY_PATH / syslibs\n' "chromium"
      fails=$((fails+1))
    fi
  else
    printf '    \033[33m--\033[0m   %-22s %s\n' "chromium" "not checked (pass --repo DIR to launch-test it)"
  fi

  # PATH hygiene: duplicates mean the env file got sourced twice unguarded.
  local dupes
  dupes=$(bash -lc 'echo $PATH | tr ":" "\n" | sort | uniq -d | wc -l')
  if [ "$dupes" = "0" ]; then
    printf '    \033[32mok\033[0m   %-22s no duplicate entries\n' "PATH"
  else
    printf '    \033[33m!\033[0m    %-22s %s duplicate entries\n' "PATH" "$dupes"
  fi

  echo
  if [ "$fails" -eq 0 ]; then
    printf '\033[32mAll checks passed.\033[0m Open a new shell, or: . %s\n' "$ENV_FILE"
    return 0
  fi
  printf '\033[31m%s check(s) failed.\033[0m\n' "$fails"
  return 1
}

# ------------------------------------------------------------------- main --
if [ "$SELF_TEST_ONLY" = true ]; then
  self_test; exit $?
fi

preflight
install_node
install_java
install_npm_globals
[ "$SKIP_ANDROID" = false ] && install_android
install_gcloud
install_small_tools
write_env
stage_syslibs
write_env         # rewrite now syslibs exists, so LD_LIBRARY_PATH is populated
install_repos     # BEFORE install_browsers: each repo installs the browser build
                  # its own pinned Playwright expects, and the shim then points
                  # at a real one rather than a floating-latest download.
install_browsers
self_test
