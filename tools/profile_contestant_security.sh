#!/bin/sh
# Shows what the contestants need beyond docker's default AppArmor profile,
# to keep misc/contestant_apparmor's exceptions to what they use. On a game
# host with AppArmor and running contestants, it loads rfhs-contestant in
# complain mode without its exceptions and with docker's deny rules made
# audit rules, runs in each container the tests, Firefox, a notification and
# the wireless tools on one of its radios, loads the real profile again and
# prints the events, counted. Restart the contestants while it waits to
# include their startup. Needs root, and auditd, as the kernel log drops
# events.
#   sudo ./tools/profile_contestant_apparmor.sh [-w seconds] container...
#   sudo ./tools/profile_contestant_apparmor.sh kali-contestant parrot-contestant
set -eu

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run it as root\n' >&2
  exit 1
fi
missing_tools=""
for tool in apparmor_parser dirname docker grep mktemp rm sed sleep sort tail uniq wc; do
  command -v "${tool}" > /dev/null 2>&1 || missing_tools="${missing_tools} ${tool}"
done
if [ -n "${missing_tools}" ]; then
  printf '%s: required commands not found:%s\n' "${0##*/}" "${missing_tools}" >&2
  exit 1
fi
wait_seconds=0
if [ "${1:-}" = -w ]; then
  wait_seconds="${2:?-w needs seconds}"
  shift 2
fi
if [ "$#" -eq 0 ]; then
  printf 'usage: %s [-w seconds] container...\n' "${0}" >&2
  exit 2
fi
log=/var/log/audit/audit.log
if [ ! -r "${log}" ]; then
  printf '%s: no %s; install auditd\n' "${0##*/}" "${log}" >&2
  exit 1
fi
here="$(dirname "${0}")"
"${here}/../misc/contestant_apparmor"
profile=/etc/apparmor.d/rfhs-contestant
complain="$(mktemp -d)"
trap '"${here}/../misc/contestant_apparmor" > /dev/null; rm -rf "${complain}"' EXIT
# x needs an exec qualifier in an allow rule, and the deny rules' x adds
# nothing to file's
sed -e 's/flags=(\(.*\))/flags=(\1,complain)/' -e '/^ *\(userns\|mount\|pivot_root\)[ ,]/d' \
  -e 's/^\( *\)deny /\1audit /' -e '/^ *audit /s/ \(r\{0,1\}wkl\)x,$/ \1,/' "${profile}" > "${complain}/rfhs-contestant"
apparmor_parser -r "${complain}/rfhs-contestant"
start="$(($(wc -c < "${log}") + 1))"
if [ "${wait_seconds}" -gt 0 ]; then
  printf 'Complain mode is on; waiting %s s\n' "${wait_seconds}"
  sleep "${wait_seconds}"
fi

for c in "$@"; do
  printf '%s: contestant-checker excessive, the tests and the wireless tools\n' "${c}"
  docker exec "${c}" /usr/local/sbin/contestant-checker excessive > /dev/null 2>&1 \
    || printf '%s: contestant-checker excessive failed\n' "${c}"
  "${here}/../contestant_containers/tests/test_healthcheck.sh" "${c}" > /dev/null 2>&1 \
    || printf '%s: test_healthcheck.sh failed\n' "${c}"
  "${here}/../contestant_containers/tests/test_firefox_sandbox.sh" "${c}" > /dev/null 2>&1 \
    || printf '%s: test_firefox_sandbox.sh failed\n' "${c}"
  docker exec -i "${c}" sh -s << 'EOF'
notify-send 'AppArmor profiling' 'Works' --icon=dialog-information || printf 'notify-send failed\n'
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
done

printf 'Events from rfhs-contestant in complain mode, counted:\n'
tail -c +"${start}" "${log}" | grep 'profile="rfhs-contestant"' | grep -v 'operation="profile_' \
  | sed -e 's/.* apparmor="\([A-Z]*\)" operation="\([^"]*\)"/\1 \2/' \
    -e 's/ info="[^"]*"//' -e 's/ \(pid\|ses\|auid\|uid\|ouid\|fsuid\|requested_mask\|denied_mask\|error\|class\)=[^ ]*//g' \
    -e 's/ profile="rfhs-contestant"//' -e 's#/proc/[0-9]*/#/proc/PID/#g' -e 's#/tmp-[A-Za-z0-9]*/#/tmp-RANDOM/#g' \
  | sort | uniq -c | sort -rn
