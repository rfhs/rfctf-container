#!/bin/sh
# Tests contestant images as their build scripts do, without building or
# pushing them: one at a time, each runs with the game's privileges and four
# mac80211_hwsim radios, and gets the healthcheck benchmark, contestant-checker
# excessive, contestant_containers/tests/test_healthcheck.sh and
# contestant_containers/tests/test_firefox_sandbox.sh. Needs root,
# for the radios.
#   sudo ./tools/test_contestant_images.sh image...
# STARTUP_WAIT (default 120) is how long each gets to start its services.
set -eu

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run it as root\n' >&2
  exit 1
fi
missing_tools=""
for tool in cat dirname docker readlink sleep; do
  command -v "${tool}" > /dev/null 2>&1 || missing_tools="${missing_tools} ${tool}"
done
if [ -n "${missing_tools}" ]; then
  printf '%s: required commands not found:%s\n' "${0##*/}" "${missing_tools}" >&2
  exit 1
fi
if [ "$#" -eq 0 ]; then
  printf 'usage: %s image...\n' "${0}" >&2
  exit 2
fi

here="$(dirname "${0}")"
. "${here}/../startup/rfhs-helpers.sh"

# hwsim_radios_home: whether every mac80211_hwsim radio is back in this
# namespace, as they come back a moment after their container stops
hwsim_radios_home() {
  [ -r /sys/module/mac80211_hwsim/parameters/radios ] || return 0
  home=0
  for phy in /sys/class/ieee80211/*; do
    driver="$(readlink -f "${phy}/device/driver")"
    if [ "${driver##*/}" = mac80211_hwsim ]; then
      home=$((home + 1))
    fi
  done
  [ "${home}" -eq "$(cat /sys/module/mac80211_hwsim/parameters/radios)" ]
}

failed=""
for image in "$@"; do
  c="test-contestant-$$"
  (
    IFS='
'
    set -f
    # shellcheck disable=SC2046
    docker run -d --rm --no-healthcheck --name "${c}" $(contestant_docker_args) "${image}" > /dev/null
  )
  "${here}/give_hwsim_radios.sh" "${c}" 4
  printf 'Waiting %s s for %s to start its services...\n' "${STARTUP_WAIT:-120}" "${image}"
  sleep "${STARTUP_WAIT:-120}"
  if "${here}/bench_healthcheck.sh" -t 100 "${c}" \
    && docker exec "${c}" /usr/local/sbin/contestant-checker excessive \
    && "${here}/../contestant_containers/tests/test_healthcheck.sh" "${c}" \
    && "${here}/../contestant_containers/tests/test_firefox_sandbox.sh" "${c}"; then
    printf '%s passed\n' "${image}"
  else
    printf '%s FAILED\n' "${image}"
    failed="${failed} ${image}"
  fi
  docker stop "${c}" > /dev/null
  waited=0
  until hwsim_radios_home || [ "${waited}" -ge 30 ]; do
    sleep 1
    waited=$((waited + 1))
  done
done
if [ -n "${failed}" ]; then
  printf 'Failed:%s\n' "${failed}"
  exit 1
fi
