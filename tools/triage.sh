#!/bin/bash
# Triase log boot LineageOS 18.1 / OPPO A37.
#
# Pakai:  tools/triage.sh <logcat.txt> [dmesg.txt]
#
# Polanya diturunkan dari bug-bug nyata yang ditemukan di Fase 10 — tiap bagian
# di bawah pernah menangkap bug sungguhan, bukan daftar teoretis.

set -u
LOG="${1:-}"
DMESG="${2:-}"
[ -f "$LOG" ] || { echo "pakai: $0 <logcat.txt> [dmesg.txt]"; exit 1; }

hdr() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
none() { echo "   (bersih)"; }

hdr "1. Service crash-loop  [time_daemon, camera-provider, imsqmidaemon]"
out=$(grep -a "exited with status\|killed by signal" "$LOG" |
      sed -E "s/.*Service '([^']+)'.*/\1/" | sort | uniq -c | sort -rn |
      awk '$1 >= 3 {printf "   %5d x  %s\n", $1, $2}')
[ -n "$out" ] && echo "$out" || none
echo "   (>=3 restart = loop; oneshot normal muncul 1x)"

hdr "2. HAL gagal mendaftar  [IRadio 1.0 vs 1.1, camera.provider passthrough]"
out=$(grep -aE "must be in VINTF manifest|Could not register service|Failed to register" "$LOG" |
      sed -E 's/^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ +//' | sort -u | sed 's/^/   /')
[ -n "$out" ] && echo "$out" || none

hdr "3. Library / simbol hilang  [libril_shim, widevine]"
out=$(grep -aE "dlopen failed|CANNOT LINK|cannot locate symbol|library .* not found" "$LOG" |
      sed -E 's/^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ +//' | sed -E 's/[0-9]{4,}/N/g' |
      sort | uniq -c | sort -rn | head -15 | sed 's/^/  /')
[ -n "$out" ] && echo "$out" || none

hdr "4. Biner tidak bisa dieksekusi  [blob 64-bit di ROM 32-bit]"
out=$(grep -a "cannot execv" "$LOG" | sed -E "s/.*cannot execv\('([^']+)'\).*/\1/" |
      sort | uniq -c | sed 's/^/   /')
[ -n "$out" ] && echo "$out" || none

hdr "5. Crash Java  [ims.apk, SystemUI AssistManager]"
out=$(grep -a -A2 "FATAL EXCEPTION" "$LOG" | grep -aE "Process:|^.*Caused by|java\.[a-z]" |
      sed -E 's/^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ +E AndroidRuntime: //' |
      sed -E 's/PID: [0-9]+//' | sort | uniq -c | sort -rn | head -12 | sed 's/^/  /')
[ -n "$out" ] && echo "$out" || none

hdr "6. ANR  [com.android.phone menunggu IRadio]"
out=$(grep -a "ANR in\|am_anr" "$LOG" | sed -E 's/^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ +//' |
      sort | uniq -c | sort -rn | head -8 | sed 's/^/  /')
[ -n "$out" ] && echo "$out" || none

hdr "7. Crash native / tombstone"
out=$(grep -aE "Fatal signal|tombstoned: received|>>> .* <<<" "$LOG" |
      sed -E 's/^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ +//' | sort -u | head -10 | sed 's/^/   /')
[ -n "$out" ] && echo "$out" || none

hdr "8. Watchdog  [penyebab reboot 60 detik di 10.1]"
out=$(grep -aE "WATCHDOG|Watchdog.*blocked|watchdog.*timeout" "$LOG" |
      sed -E 's/^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ +//' | sort -u | head -8 | sed 's/^/   /')
[ -n "$out" ] && echo "$out" || none

hdr "9. SELinux"
tot=$(grep -ac "avc: denied" "$LOG"); enf=$(grep -a "avc: denied" "$LOG" | grep -ac "permissive=0")
echo "   total denial: $tot   |   enforcing (permissive=0): $enf"
[ "$enf" -gt 0 ] && echo "   ^ yang permissive=0 BENAR-BENAR memblokir; sisanya cuma dicatat"
grep -a "avc: denied" "$LOG" | sed -E 's/.*scontext=u:r:([a-zA-Z0-9_-]+):.*tclass=([a-z_]+).*/\1 -> \2/' |
  sort | uniq -c | sort -rn | head -8 | sed 's/^/   /'

hdr "10. HAL menggantung di getService"
out=$(grep -aE "Waited one second for|Waiting for HAL|hwservicemanager.*not registered" "$LOG" |
      sed -E 's/^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ +//' | sort -u | head -8 | sed 's/^/   /')
[ -n "$out" ] && echo "$out" || none

hdr "11. Waktu boot"
grep -aE "boot_progress_|Boot is finished" "$LOG" |
  sed -E 's/^([0-9-]+ [0-9:.]+).*(boot_progress_[a-z_]+|Boot is finished).*/   \1  \2/' | head -12
if ! grep -aq "boot_progress_" "$LOG"; then
  echo "   TIDAK ADA penanda boot_progress — log diambil terlalu lambat, ring buffer"
  echo "   sudah berputar melewati masa boot. Perbesar buffer:"
  echo "       adb shell setprop persist.logd.size 16M   lalu reboot"
fi
[ -n "$DMESG" ] && [ -f "$DMESG" ] && {
  echo "   --- kernel ---"
  grep -aE "Freeing unused kernel|Run /init" "$DMESG" | sed 's/^/   /' | head -3
}

hdr "12. Fase system_server terlama"
grep -a "took to complete" "$LOG" |
  sed -E 's/.*: ([A-Za-z0-9_.$-]+) took to complete: ([0-9]+)ms/\2 \1/' |
  sort -rn | head -8 | awk '{printf "   %6s ms  %s\n", $1, $2}'

printf '\n'
