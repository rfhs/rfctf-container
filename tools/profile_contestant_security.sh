#!/bin/sh
# Shows what contestant images need beyond docker's default seccomp and
# AppArmor profiles, to keep startup/rfhs-contestant-seccomp.json's and
# misc/contestant_apparmor's exceptions to what they use. One at a time, each
# image runs as the build scripts run it, with four mac80211_hwsim radios, but
# under startup/rfhs-contestant-seccomp.json without its own rules and with
# every syscall it doesn't allow logged instead of denied and, on hosts with AppArmor, rfhs-contestant
# in complain mode without its exceptions and with docker's deny rules made
# audit rules. Once its services have started it gets contestant-checker
# excessive, the tests, Firefox, a notification and the wireless tools on one
# of its radios; then the real AppArmor profile is loaded again and the
# events are printed, counted. Needs root, free radios and auditd, as the
# kernel log drops events.
#   sudo ./tools/profile_contestant_security.sh image...
# STARTUP_WAIT (default 120) is how long each gets to start its services.
set -eu

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run it as root\n' >&2
  exit 1
fi
missing_tools=""
for tool in cat dirname docker grep mktemp python3 readlink rm sed sleep sort tail uniq wc; do
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
log=/var/log/audit/audit.log
if [ ! -r "${log}" ]; then
  printf '%s: no %s; install auditd\n' "${0##*/}" "${log}" >&2
  exit 1
fi
here="$(dirname "${0}")"
. "${here}/../startup/rfhs-helpers.sh"

work="$(mktemp -d)"
apparmor=""
if [ "$(cat /sys/module/apparmor/parameters/enabled 2> /dev/null)" = Y ]; then
  apparmor=y
  "${here}/../misc/contestant_apparmor"
fi
c="profile-contestant-$$"
trap 'docker rm -f "${c}" > /dev/null 2>&1 || true; [ -z "${apparmor}" ] || "${here}/../misc/contestant_apparmor" > /dev/null; rm -rf "${work}"' EXIT
python3 -I - "${here}/../startup/rfhs-contestant-seccomp.json" "${work}/rfhs-contestant-seccomp.json" << 'EOF'
import json
import sys
with open(sys.argv[1]) as f:
    profile = json.load(f)
profile['defaultAction'] = 'SCMP_ACT_LOG'
del profile['defaultErrnoRet']
profile['syscalls'] = [s for s in profile['syscalls'] if not s.get('comment', '').startswith('rfhs-contestant:')]
with open(sys.argv[2], 'w') as f:
    json.dump(profile, f)
EOF
if [ -n "${apparmor}" ]; then
  # x needs an exec qualifier in an allow rule, and the deny rules' x adds
  # nothing to file's
  sed -e 's/flags=(\(.*\))/flags=(\1,complain)/' -e '/^ *\(userns\|mount\|pivot_root\)[ ,]/d' \
    -e 's/^\( *\)deny /\1audit /' -e '/^ *audit /s/ \(r\{0,1\}wkl\)x,$/ \1,/' \
    /etc/apparmor.d/rfhs-contestant > "${work}/rfhs-contestant"
  apparmor_parser -r "${work}/rfhs-contestant"
fi
start="$(($(wc -c < "${log}") + 1))"

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

for image in "$@"; do
  (
    IFS='
'
    set -f
    # shellcheck disable=SC2046
    docker run -d --rm --no-healthcheck --name "${c}" $(contestant_docker_args "${work}") "${image}" > /dev/null
  )
  "${here}/give_hwsim_radios.sh" "${c}" 4
  printf '%s: waiting %s s for its services, then the tests and the wireless tools\n' "${image}" "${STARTUP_WAIT:-120}"
  sleep "${STARTUP_WAIT:-120}"
  docker exec "${c}" /usr/local/sbin/contestant-checker excessive > /dev/null 2>&1 \
    || printf '%s: contestant-checker excessive failed\n' "${image}"
  "${here}/../contestant_containers/tests/test_healthcheck.sh" "${c}" > /dev/null 2>&1 \
    || printf '%s: test_healthcheck.sh failed\n' "${image}"
  "${here}/../contestant_containers/tests/test_firefox_sandbox.sh" "${c}" > /dev/null 2>&1 \
    || printf '%s: test_firefox_sandbox.sh failed\n' "${image}"
  docker exec -i "${c}" sh -s << 'EOF'
notify-send 'Profiling' 'Works' --icon=dialog-information || printf 'notify-send failed\n'
radio="$(iw dev | sed -n 's/^[[:space:]]*Interface //p' | sort | head -n 1)"
if [ -z "${radio}" ]; then
  printf 'No radio, so no wireless tools\n'
  exit 0
fi
# run command...: runs it for up to 15 s, as its own output goes nowhere
run() {
  timeout -s INT 15 "$@" < /dev/null > /dev/null 2>&1 || true
}
run macchanger -r "${radio}"
run airmon-ng start "${radio}"
monitor="$(iw dev | awk '/Interface/ { i = $2 } /type monitor/ { print i; exit }')"
monitor="${monitor:-${radio}}"
work="$(mktemp -d)"
run airodump-ng --write-interval 1 -w "${work}/airodump" "${monitor}"
run dumpcap -i "${monitor}" -a duration:5 -w "${work}/dumpcap.pcapng"
run tshark -i "${monitor}" -a duration:5
run tcpdump -i "${monitor}" -c 20
run hcxdumptool -i "${monitor}" -w "${work}/hcxdumptool.pcapng" --rds=1
run wash -i "${monitor}"
run mdk4 "${monitor}" b -s 50
run kismet -c "${monitor}" --no-ncurses
run airmon-ng stop "${monitor}"
rm -rf "${work}"
EOF
  docker stop "${c}" > /dev/null
  waited=0
  until hwsim_radios_home || [ "${waited}" -ge 30 ]; do
    sleep 1
    waited=$((waited + 1))
  done
done

printf 'Syscalls the seccomp profile would deny, counted by command:\n'
tail -c +"${start}" "${log}" | grep 'type=SECCOMP' | grep 'code=0x7ffc0000' \
  | sed -n 's/.* comm=\("[^"]*"\|[0-9A-F]*\) .* syscall=\([0-9]*\) .*/\2 \1/p' | sort | uniq -c | sort -rn \
  | while read -r count syscall comm; do
    name="$(ausyscall "${syscall}" 2> /dev/null || printf 'syscall %s' "${syscall}")"
    printf '%7s %s %s\n' "${count}" "${name}" "${comm}"
  done
if [ -n "${apparmor}" ]; then
  printf 'Events from rfhs-contestant in complain mode, counted:\n'
  tail -c +"${start}" "${log}" | grep 'profile="rfhs-contestant"' | grep -v 'operation="profile_' \
    | sed -e 's/.* apparmor="\([A-Z]*\)" operation="\([^"]*\)"/\1 \2/' \
      -e 's/ info="[^"]*"//' -e 's/ \(pid\|ses\|auid\|uid\|ouid\|fsuid\|requested_mask\|denied_mask\|error\|class\)=[^ ]*//g' \
      -e 's/ profile="rfhs-contestant"//' -e 's#/proc/[0-9]*/#/proc/PID/#g' -e 's#/tmp-[A-Za-z0-9]*/#/tmp-RANDOM/#g' \
    | sort | uniq -c | sort -rn
fi
