#!/bin/sh
# Runs the image with the docker arguments 08_fosphor_knob.start would use,
# against its own Xvfb (see README.md).
#   startup/tests/fosphor_knob_start_test.sh [image]    (default rfhs/fosphor_knob)
set -eu

image="${1:-rfhs/fosphor_knob}"
TEST_DISPLAY="${TEST_DISPLAY:-:97}"
here="$(cd "$(dirname "${0}")" && pwd)"
# shellcheck source=SCRIPTDIR/../rfhs-helpers.sh
. "${here}/../rfhs-helpers.sh"

for cmd in Xvfb xauth docker; do
  if ! command -v "${cmd}" > /dev/null 2>&1; then
    printf '%s is required\n' "${cmd}"
    exit 1
  fi
done
num="$(x_display_number "${TEST_DISPLAY}")"
if [ -e "/tmp/.X11-unix/X${num}" ]; then
  printf 'Display %s is in use, pick another with TEST_DISPLAY\n' "${TEST_DISPLAY}"
  exit 1
fi

work="$(mktemp -d)"
xvfb=""
# shellcheck disable=SC2329
cleanup() {
  if [ -n "${xvfb}" ]; then
    kill "${xvfb}" 2> /dev/null || true
  fi
  rm -rf "${work}"
}
trap cleanup EXIT INT TERM

# A FamilyLocal cookie for this host's name, like display managers write
cookie="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
: > "${work}/server auth"
xauth -q -f "${work}/server auth" add "${TEST_DISPLAY}" . "${cookie}"
Xvfb "${TEST_DISPLAY}" -nolisten tcp -auth "${work}/server auth" -screen 0 1280x800x24 > "${work}/xvfb.log" 2>&1 &
xvfb=$!
if ! wait_for_x "${TEST_DISPLAY}" 30; then
  cat "${work}/xvfb.log"
  exit 1
fi

found="$(x_server_auth "${TEST_DISPLAY}")"
if [ "${found}" != "${work}/server auth" ]; then
  printf 'FAIL x_server_auth found "%s" instead of the Xvfb cookie\n' "${found}"
  exit 1
fi
printf 'PASS x_server_auth found the X server cookie (a path with a space)\n'

args="$(x11_docker_args "${TEST_DISPLAY}"; gpu_docker_args; usb_input_docker_args)"
printf 'docker run arguments for this host:\n%s\n' "${args}"

# CI runners have no USB or input devices; one option per line, like the arguments
skip=""
if ! ls /dev/bus/usb/*/* > /dev/null 2>&1; then
  skip="${skip}
--no-usb"
fi
if ! ls /dev/input/event* > /dev/null 2>&1; then
  skip="${skip}
--no-input"
fi

status=0
(
  IFS='
'
  set -f
  # shellcheck disable=SC2086
  docker run -i --rm --network none \
    --tmpfs /run:mode=0755,nosuid,nodev,nr_inodes=800k,size=20%,strictatime \
    --userns host ${args} "${image}" python3 - ${skip} < "${here}/fosphor_knob_container_check.py"
) || status=1

# Without the cookie the X server has to refuse it, or the run above proved nothing
docker run -i --rm --network none -e DISPLAY="${TEST_DISPLAY}" \
  -v /tmp/.X11-unix:/tmp/.X11-unix --ipc=host --hostname "$(uname -n)" \
  "${image}" python3 - --no-x < "${here}/fosphor_knob_container_check.py" || status=1
# And with the cookie but without --ipc=host, MIT-SHM has to fail
noipc="$(x11_docker_args "${TEST_DISPLAY}" | grep -v -x -e '--ipc=host')"
(
  IFS='
'
  set -f
  # shellcheck disable=SC2086
  docker run -i --rm --network none ${noipc} "${image}" \
    python3 - --no-ipc < "${here}/fosphor_knob_container_check.py"
) || status=1
exit "${status}"
