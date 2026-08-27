#!/usr/bin/env bash
#
# Is this machine able to do Expo/Android development, and how well?
#
# Run this on a candidate host BEFORE migrating to it. The answer that matters
# is not on any spec sheet: whether the CPU you have been given exposes
# hardware virtualization. Without it the Android emulator still runs, but in
# software (TCG) at roughly the speeds quoted below, and no amount of root
# inside the guest changes that — the hypervisor decides.
#
# Exit status: 0 if the emulator can be accelerated, 1 if not (everything else
# is reported but never fails the run).
#
set -uo pipefail

ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mno\033[0m    %s\n' "$*"; }
note() { printf '        %s\n' "$*"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

hdr "Machine"
printf '  %-18s %s\n' "cpu"    "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
printf '  %-18s %s\n' "cores"  "$(nproc)"
printf '  %-18s %s\n' "memory" "$(free -h 2>/dev/null | awk 'NR==2{print $2}')"
printf '  %-18s %s\n' "free disk in \$HOME" "$(df -Ph "$HOME" | awk 'NR==2{print $4}')"
printf '  %-18s %s\n' "os"     "$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
printf '  %-18s %s\n' "kernel" "$(uname -r)"
if command -v systemd-detect-virt >/dev/null; then
  printf '  %-18s %s\n' "virtualization" "$(systemd-detect-virt || echo none)"
fi

hdr "Android emulator acceleration"
flags=$(grep -m1 '^flags' /proc/cpuinfo | tr ' ' '\n' | grep -Ex 'vmx|svm' | tr '\n' ' ')
accel=0

if [ -n "${flags// /}" ]; then
  ok "CPU exposes hardware virtualization (${flags% })"
else
  bad "CPU exposes NO vmx/svm flag"
  note "Nested virtualization is switched off by the HOST hypervisor."
  note "Nothing inside this machine — root included — can turn it on."
  accel=1
fi

if [ -e /dev/kvm ]; then
  if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ok "/dev/kvm exists and is usable by $(id -un)"
  else
    bad "/dev/kvm exists but $(id -un) cannot use it"
    note "Fix (needs root): usermod -aG kvm $(id -un), then log out and back in."
    accel=1
  fi
else
  bad "/dev/kvm does not exist"
  accel=1
fi

# The authoritative answer, if the SDK is installed: ask the emulator itself.
EMU="${ANDROID_HOME:-$HOME/opt/Android/Sdk}/emulator/emulator"
if [ -x "$EMU" ]; then
  out=$("$EMU" -accel-check 2>&1 | tr '\n' ' ')
  case "$out" in
    *"is installed and usable"*|*"accel:0"*|*"accel: 0"*) ok  "emulator -accel-check: $out" ;;
    *) bad "emulator -accel-check: $out"; accel=1 ;;
  esac
else
  note "(Android SDK not installed here, so the emulator's own check was skipped.)"
fi

hdr "Verdict"
if [ "$accel" -eq 0 ]; then
  ok "The Android emulator will run at full speed on this host."
else
  bad "The Android emulator will run in SOFTWARE emulation on this host."
  cat <<'MSG'

        Measured on one such host (Pixel 6, API 35, google_apis/x86_64):

          cold boot to sys.boot_completed   805 s  (13.4 min)
          adb exec-out screencap            ~14 s
          adb shell input tap / swipe       ~1.4 s
          adb shell input text / keyevent   ~1.1-1.3 s

        Load average while running was ~1.0: TCG is single-threaded per vCPU,
        so extra cores do not help and neither does extra RAM.

        Input is tolerable. SCREENSHOTS are what hurt, and screenshot-based
        verification is how Android UI usually gets checked — a sweep of a few
        dozen shots becomes a different kind of activity.

        Still fine on such a host:
          - Android APK and AAB builds (Gradle needs no KVM)
          - the entire web surface, the Firebase emulators, every CLI

        To get acceleration, on the PHYSICAL host:
          1. Intel: options kvm_intel nested=1   (/etc/modprobe.d/kvm.conf)
             AMD:   options kvm_amd   nested=1
          2. Give the guest a CPU model that passes the flag through —
             libvirt: <cpu mode='host-passthrough'/>
          3. Reboot the guest.
        On a hosted VPS this is the provider's setting, not yours. Ask before
        you migrate; most cheap tiers do not offer it.

        Alternative that needs no hypervisor change: run the emulator (or a
        real phone) elsewhere and drive it over ADB TCP. screencap, input and
        install all work identically over the network.
MSG
fi

hdr "Toolchain"
for t in node npm java firebase gcloud gh sentry-cli jq lsof adb python3; do
  if command -v "$t" >/dev/null; then
    printf '  \033[32mok\033[0m    %-12s %s\n' "$t" "$(command -v "$t")"
  else
    printf '  \033[33m--\033[0m    %-12s not installed\n' "$t"
  fi
done
printf '\n  Install everything missing with: bootstrap-linux.sh\n\n'

exit "$accel"
