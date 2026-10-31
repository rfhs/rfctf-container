#!/bin/sh
# Tests that Firefox sandboxes its content processes in a running contestant
# container: each runs in a user namespace of its own, under a seccomp
# filter. Docker's default seccomp and AppArmor profiles deny the user
# namespaces, and Firefox then runs its content without them, so this fails
# if the contestants lose seccomp=unconfined or the userns rule in
# misc/contestant_apparmor.
#   ./contestant_containers/tests/test_firefox_sandbox.sh container
set -eu

if ! command -v docker > /dev/null 2>&1; then
  printf '%s: required commands not found: docker\n' "${0##*/}" >&2
  exit 1
fi
if [ -z "${1:-}" ]; then
  printf 'Usage: %s container\n' "${0}" >&2
  exit 2
fi

docker exec -i "${1}" sh -s << 'EOF'
firefox=""
for f in firefox firefox-esr firefox-bin; do
  if command -v "${f}" > /dev/null 2>&1; then
    firefox="${f}"
    break
  fi
done
if [ -z "${firefox}" ]; then
  printf 'FAIL: Firefox is not installed\n'
  exit 1
fi
# ppid pid: the parent's, from after the command name, which can have spaces
ppid() {
  sed 's/.*) [A-Za-z] \([0-9]*\) .*/\1/' "/proc/${1}/stat" 2> /dev/null
}
# descends pid ancestor: whether ancestor is pid or one of its ancestors
descends() {
  d="${1}"
  while [ -n "${d}" ] && [ "${d}" -gt 1 ]; do
    [ "${d}" = "${2}" ] && return 0
    d="$(ppid "${d}")"
  done
  return 1
}
profile="$(mktemp -d)"
"${firefox}" --headless --no-remote --profile "${profile}" about:blank > "${profile}.log" 2>&1 &
main=$!
own_userns="$(readlink /proc/self/ns/user)"
sandboxed=""
waited=0
while [ -z "${sandboxed}" ] && [ "${waited}" -lt 60 ]; do
  sleep 2
  waited=$((waited + 2))
  unsandboxed=""
  for p in $(pgrep -f -- -contentproc); do
    descends "${p}" "${main}" || continue
    tr '\0' ' ' < "/proc/${p}/cmdline" 2> /dev/null | grep -q 'forkserver *$' && continue
    userns="$(readlink "/proc/${p}/ns/user" 2> /dev/null)" || continue
    seccomp="$(sed -n 's/^Seccomp:[[:space:]]*//p' "/proc/${p}/status" 2> /dev/null)"
    if [ "${userns}" != "${own_userns}" ] && [ "${seccomp}" = 2 ]; then
      sandboxed="${p}"
    else
      unsandboxed="${unsandboxed} ${p} (${userns}, seccomp ${seccomp})"
    fi
  done
done
pkill -f -- "--profile ${profile}" 2> /dev/null || true
sleep 2
pkill -KILL -f -- "--profile ${profile}" 2> /dev/null || true
if [ -n "${sandboxed}" ]; then
  printf 'PASS: %s runs its content process %s in its own user namespace under seccomp\n' "${firefox}" "${sandboxed}"
  rm -rf "${profile}" "${profile}.log"
  exit 0
fi
if [ -n "${unsandboxed}" ]; then
  printf 'FAIL: %s content processes not sandboxed, besides the container user namespace %s:%s\n' \
    "${firefox}" "${own_userns}" "${unsandboxed}"
else
  printf 'FAIL: %s started no content process in 60 s; its output:\n' "${firefox}"
  tail -n 20 "${profile}.log"
fi
rm -rf "${profile}" "${profile}.log"
exit 1
EOF
