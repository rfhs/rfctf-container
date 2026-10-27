#!/bin/sh
# Starts openwrt and rfctf-client on mac80211_hwsim radios, as their build
# scripts do but without docker's healthcheck, for tools/bench_healthcheck.sh;
# "stop" stops them and unloads mac80211_hwsim. Needs root.
#   sudo ./tools/hwsim_containers.sh start [openwrt image] [rfctf-client image]
#   sudo ./tools/hwsim_containers.sh stop
# The containers are bench-openwrt and bench-rfctf-client. rfctf-client gets
# the radios whose interfaces are wlan10 to wlan25, which its ldm.conf uses,
# and openwrt 10 others; all hwsim radios share one medium, so the clients
# find the APs. Only mac80211_hwsim radios are moved.
set -eu

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run it as root\n' >&2
  exit 1
fi
missing_tools=""
for tool in cat docker grep id iw lsmod modprobe readlink sleep wc; do
  command -v "${tool}" > /dev/null 2>&1 || missing_tools="${missing_tools} ${tool}"
done
if [ -n "${missing_tools}" ]; then
  printf '%s: required commands not found:%s\n' "${0##*/}" "${missing_tools}" >&2
  exit 1
fi

case "${1:-}" in
  start) ;;
  stop)
    docker stop bench-openwrt bench-rfctf-client 2> /dev/null || true
    # the radios come back from the containers' namespaces as these go away
    sleep 2
    if lsmod | grep -q '^mac80211_hwsim '; then
      modprobe -r mac80211_hwsim
    fi
    exit 0
    ;;
  *)
    printf 'usage: %s start [openwrt image] [rfctf-client image] | stop\n' "${0}" >&2
    exit 2
    ;;
esac
openwrt_image="${2:-rfhs/openwrt:latest}"
client_image="${3:-rfhs/rfctf-client:latest}"

if lsmod | grep -q '^mac80211_hwsim '; then
  printf 'mac80211_hwsim is already loaded; run "%s stop" or unload it first\n' "${0}" >&2
  exit 1
fi
for c in bench-openwrt bench-rfctf-client; do
  if docker container inspect "${c}" > /dev/null 2>&1; then
    printf '%s already exists\n' "${c}" >&2
    exit 1
  fi
done

# wlan names are the lowest free ones, so other wifi cards on the host push
# the radios' up; 30 leaves room for a few
modprobe mac80211_hwsim radios=30
sleep 2

client_phys=""
openwrt_phys=""
openwrt_count=0
for phy in /sys/class/ieee80211/*; do
  driver="$(readlink -f "${phy}/device/driver")"
  if [ "${driver##*/}" != mac80211_hwsim ]; then
    continue
  fi
  for dev in "${phy}"/device/net/*; do
    case "${dev##*/}" in
      wlan1[0-9] | wlan2[0-5])
        client_phys="${client_phys} ${phy##*/}"
        continue 2
        ;;
    esac
  done
  if [ "${openwrt_count}" -lt 10 ]; then
    openwrt_phys="${openwrt_phys} ${phy##*/}"
    openwrt_count=$((openwrt_count + 1))
  fi
done
if [ "$(echo "${client_phys}" | wc -w)" -ne 16 ] || [ "${openwrt_count}" -ne 10 ]; then
  printf 'Expected hwsim radios for wlan10 to wlan25 and 10 more, got%s and%s\n' "${client_phys}" "${openwrt_phys}" >&2
  modprobe -r mac80211_hwsim
  exit 1
fi
for phy in ${client_phys} ${openwrt_phys}; do
  for soft in /sys/class/ieee80211/"${phy}"/rfkill*/soft; do
    if [ -w "${soft}" ] && [ "$(cat "${soft}")" != 0 ]; then
      echo 0 > "${soft}"
    fi
  done
done

docker run -d --rm --no-healthcheck --name bench-openwrt --network none \
  --tmpfs /run:mode=0755,nosuid,nodev,nr_inodes=800k,size=20%,strictatime \
  --tmpfs /tmp:mode=0755,nosuid,nodev,nr_inodes=800k,size=20% \
  --cap-add net_raw --cap-add net_admin \
  "${openwrt_image}"
docker run -d --rm --no-healthcheck --name bench-rfctf-client --network none \
  --cap-add net_raw --cap-add net_admin \
  "${client_image}"

move() {
  pid="$(docker inspect -f '{{.State.Pid}}' "${1}")"
  for phy in ${2}; do
    iw phy "${phy}" set netns "${pid}"
  done
}
move bench-openwrt "${openwrt_phys}"
move bench-rfctf-client "${client_phys}"
printf 'bench-openwrt has%s, bench-rfctf-client has%s\n' "${openwrt_phys}" "${client_phys}"
