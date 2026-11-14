#!/bin/sh
# Scans from a free mac80211_hwsim radio on the host, as a contestant's radio
# hears the game, and prints each BSS as "bssid freq encryption ssid":
# encryption is open without the privacy bit, wep with it and no RSN or WPA
# element, or wpa with one. With ssids it probes for them too, which hidden
# networks need, and prints only those. Needs root and a radio no container
# holds.
#   sudo ./tools/scan_hwsim.sh [ssid...]
set -eu

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run it as root\n' >&2
  exit 1
fi
missing_tools=""
for tool in awk ip iw readlink rfkill sleep; do
  command -v "${tool}" > /dev/null 2>&1 || missing_tools="${missing_tools} ${tool}"
done
if [ -n "${missing_tools}" ]; then
  printf '%s: required commands not found:%s\n' "${0##*/}" "${missing_tools}" >&2
  exit 1
fi

dev="rfhsscan0"
scan_phy=""
for phy in /sys/class/ieee80211/*; do
  driver="$(readlink -f "${phy}/device/driver" || true)"
  if [ "${driver##*/}" = mac80211_hwsim ]; then
    scan_phy="${phy##*/}"
    break
  fi
done
if [ -z "${scan_phy}" ]; then
  printf 'No mac80211_hwsim radio is left on the host to scan from\n' >&2
  exit 1
fi

iw phy "${scan_phy}" interface add "${dev}" type managed
trap 'iw dev "${dev}" del' EXIT
for rfkill_dir in "/sys/class/ieee80211/${scan_phy}"/rfkill*; do
  if [ -e "${rfkill_dir}" ]; then
    rfkill unblock "${rfkill_dir##*/rfkill}"
  fi
done
ip link set "${dev}" up
for _ in 1 2 3; do
  iw dev "${dev}" scan ssid "" "$@" > /dev/null || true
  sleep 1
done
wanted="$(printf '%s\n' "$@")"
iw dev "${dev}" scan dump | wanted="${wanted}" awk '
  BEGIN { n = split(ENVIRON["wanted"], w, "\n"); for (i = 1; i <= n; i++) if (w[i] != "") want[w[i]] = 1 }
  function flush() {
    if (bssid != "" && (n == 0 || ssid in want))
      printf "%s %s %s %s\n", bssid, freq, (wpa ? "wpa" : (privacy ? "wep" : "open")), ssid
  }
  /^BSS / { flush(); bssid = tolower(substr($2, 1, 17)); freq = ""; ssid = ""; privacy = 0; wpa = 0; next }
  /^\tfreq:/ { freq = $2 }
  /^\tcapability:/ { privacy = ($0 ~ / Privacy( |$)/) }
  /^\tSSID: / { ssid = substr($0, 8) }
  /^\t(RSN|WPA):/ { wpa = 1 }
  END { flush() }' | sort -k4
