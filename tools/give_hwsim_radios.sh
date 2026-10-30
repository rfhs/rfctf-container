#!/bin/sh
# Moves mac80211_hwsim radios into a running container, for a build script's
# test. It loads mac80211_hwsim with that many radios when it isn't loaded,
# and reloads it with that many when too few are free but none is in another
# namespace; it fails rather than take radios another container has. Needs
# root.
#   sudo ./tools/give_hwsim_radios.sh container count
set -eu

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run it as root\n' >&2
  exit 1
fi
missing_tools=""
for tool in cat docker grep iw lsmod modprobe readlink rfkill sleep wc; do
  command -v "${tool}" > /dev/null 2>&1 || missing_tools="${missing_tools} ${tool}"
done
if [ -n "${missing_tools}" ]; then
  printf '%s: required commands not found:%s\n' "${0##*/}" "${missing_tools}" >&2
  exit 1
fi
if [ "$#" -ne 2 ]; then
  printf 'usage: %s container count\n' "${0}" >&2
  exit 2
fi
container="${1}"
count="${2}"

# free_radios: the mac80211_hwsim phys in this namespace, one per line
free_radios() {
  for phy in /sys/class/ieee80211/*; do
    if [ -e "${phy}" ]; then
      driver="$(readlink -f "${phy}/device/driver")"
      if [ "${driver##*/}" = mac80211_hwsim ]; then
        printf '%s\n' "${phy##*/}"
      fi
    fi
  done
}

if ! lsmod | grep -q '^mac80211_hwsim '; then
  modprobe mac80211_hwsim radios="${count}"
  sleep 2
fi
free="$(free_radios)"
free_count="$(printf '%s' "${free}" | grep -c . || true)"
if [ "${free_count}" -lt "${count}" ]; then
  radios="$(cat /sys/module/mac80211_hwsim/parameters/radios)"
  if [ "${free_count}" -ne "${radios}" ]; then
    printf '%s: %s needs %s mac80211_hwsim radios, but only %s of the %s are free; the others are in other containers\n' \
      "${0##*/}" "${container}" "${count}" "${free_count}" "${radios}" >&2
    exit 1
  fi
  modprobe -r mac80211_hwsim
  modprobe mac80211_hwsim radios="${count}"
  sleep 2
  free="$(free_radios)"
fi

pid="$(docker inspect -f '{{.State.Pid}}' "${container}")"
given=""
for phy in ${free}; do
  if [ "$(printf '%s' "${given}" | wc -w)" -ge "${count}" ]; then
    break
  fi
  for rfkill_dir in "/sys/class/ieee80211/${phy}"/rfkill*; do
    if [ -e "${rfkill_dir}" ]; then
      rfkill unblock "${rfkill_dir##*/rfkill}"
    fi
  done
  iw phy "${phy}" set netns "${pid}"
  given="${given} ${phy}"
done
printf '%s has the mac80211_hwsim radios%s\n' "${container}" "${given}"
