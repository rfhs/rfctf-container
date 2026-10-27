#!/bin/sh
set -eu
missing_tools=""
for tool in awk date docker grep head hostname iw lsmod mountpoint readlink sleep sudo; do
  command -v "${tool}" > /dev/null 2>&1 || missing_tools="${missing_tools} ${tool}"
done
if [ -n "${missing_tools}" ]; then
  printf '%s: required commands not found:%s\n' "${0##*/}" "${missing_tools}" >&2
  exit 1
fi
if [ "$(date -r portage_and_overlay.tar.xz +%s)" -lt "$(date -d "7 days ago" +%s)" ]; then
  printf "portage_and_overlay.tar.xz is too old, aborting for safety\n"
  exit 1
fi
VERS="1.5"
DISTRO="rfctf-client"
CONTAINER_NAME="rfhs-${DISTRO}-ci"
if docker container inspect "${CONTAINER_NAME}" > /dev/null 2>&1; then
  printf "Found existing %s container... QUITTING\n" "${CONTAINER_NAME}"
  exit 1
fi
docker pull docker.io/pentoolinux/pentoo-core
docker build --no-cache-filter "${DISTRO}" . --progress=plain -f "Dockerfile.${DISTRO}" -t rfhs/${DISTRO}:${VERS}

## You know what all the cool kids like?  CI!  Time to test like a boss
# This is probably unsafe AND requires root.  I'd rather CI than no CI though, so for now it's happening
# This is unsafe in the following ways:
# This just modprobes and rips out the module, needed or otherwise, which means it's not parallel safe at all

rfkill_check() {
	#take phy and check blocks
	if [ -z "${1}" ]; then
		printf "Fatal, rfkill_check requires a phy to be passed in\n"
		exit 1
	fi
	#first we have to find the rfkill index
	#this is available as /sys/class/net/wlan0/phy80211/rfkill## but that's a bit difficult to parse
	index="$(sudo rfkill list | grep "${1}:" | head -n1 | awk -F: '{print $1}')"
	if [ -z "$index" ]; then
		return 187
	fi
	if ! rfkill_status="$(sudo rfkill list "${index}" 2>&1)"; then
		printf "rfkill error: %s\n" "${rfkill_status}"
		return 187
	elif [ -z "${rfkill_status}" ]; then
		printf "rfkill had no output, something went wrong.\n"
		exit 1
	else
		soft=$(printf "%s" "${rfkill_status}" | grep -i soft | awk '{print $3}')
		hard=$(printf "%s" "${rfkill_status}" | grep -i hard | awk '{print $3}')
		if [ "${soft}" = "yes" ] && [ "${hard}" = "no" ]; then
			return 1
		elif [ "${soft}" = "no" ] && [ "${hard}" = "yes" ]; then
			return 2
		elif [ "${soft}" = "yes" ] && [ "${hard}" = "yes" ]; then
			return 3
		fi
	fi
	return 0
}

rfkill_unblock() {
	#attempt unblock and CHECK SUCCESS
	#rfkill_status="$(sudo rfkill unblock "${1#phy}" 2>&1)"
	#if [ $? != 0 ]; then
		if ! rfkill_status="$(sudo rfkill unblock "${index}" 2>&1)"; then
      if [ "$(printf "%s" "${rfkill_status}" | grep -c "Usage")" -eq 1 ]; then
				printf "Missing parameters in rfkill! Report this"
			else
				printf "rfkill error: %s\n" "${rfkill_status}"
			fi
			printf "Unable to unblock.\n"
			return 1
		fi
	#fi

	sleep 1
	return 0
}

create_ns_link() {
  PID="$(docker inspect -f '{{.State.Pid}}' "${CONTAINER_NAME}")"
  if [ -z "${PID}" ]; then
    printf "Unable to identify process id for %s, skipping.\n" "${CONTAINER_NAME}"
    exit 1
  fi
  sudo mkdir -p /run/netns/
  if mountpoint -q -- "/run/netns/${CONTAINER_NAME}"; then
    # Remove the stale namespace mounting
	  printf "Stale namespace found at /run/netns/%s\n" "${CONTAINER_NAME}"
    printf "Removing stale namespace\n"
    sudo ip netns delete "${CONTAINER_NAME}"
  fi
  sudo touch "/run/netns/${CONTAINER_NAME}"
  printf "Mapping namespaces of process id %s for %s to namespace name %s\n" "${PID}" "${CONTAINER_NAME}" "${CONTAINER_NAME}"
  sudo mount -o bind "/proc/${PID}/ns/net" "/run/netns/${CONTAINER_NAME}"
}

# Start by removing hwsim and then making 26 hwsim devices
if lsmod | grep -q mac80211_hwsim; then
  sudo modprobe -r mac80211_hwsim
  sleep 5
fi
sudo modprobe mac80211_hwsim radios=26
# ldm_checker --excessive checks dhcpcd on a dummy interface
sudo modprobe dummy

# Get a list of the radios (a little safer than assuming)
#CONTAINER_PHYS="phy10 phy11 phy12 phy13 phy14 phy15 phy16 phy17 phy18 phy19 phy20 phy21 phy22 phy23 phy24 phy25"
# Not airmon-ng: before aircrack-ng f333a6a7 (not in 1.7) it takes the driver
# from the device's uevent, which newer kernels leave empty for hwsim radios
CONTAINER_PHYS="$(for phy in /sys/class/ieee80211/*; do
  driver="$(readlink -f "${phy}/device/driver")"
  if [ "${driver##*/}" = mac80211_hwsim ]; then printf '%s\n' "${phy##*/}"; fi
done)"
# Start the container; docker's own healthcheck runs would race the tests' runs of the checker
docker run -d --rm --no-healthcheck --network none --name "${CONTAINER_NAME}" \
  --cap-add net_raw --cap-add net_admin \
  "rfhs/${DISTRO}:${VERS}"
  #--privileged --userns host \
# Give it radios
create_ns_link
for phy in ${CONTAINER_PHYS}; do
  while true; do
    if iw phy "${phy}" info > /dev/null 2>&1; then
      break
    fi
    printf "Unable to find %s, waiting...\n" "${phy}"
    sleep 1
  done
  rfkill_check "${phy}" || rfkill_unblock "${phy}"
  sleep 1
  sudo iw phy "${phy}" set netns name "${CONTAINER_NAME}"
done
sleep "${STARTUP_WAIT:-90}"
# there are no APs for the clients here, so the healthcheck runs as --test
if ../tools/bench_healthcheck.sh -t 100 -x './ldm_checker --test' "${CONTAINER_NAME}" \
  && docker exec "${CONTAINER_NAME}" ./ldm_checker --excessive; then
  docker tag "rfhs/${DISTRO}:${VERS}" "rfhs/${DISTRO}:latest"
  if [ "$(hostname)" = "Nu" ] ; then
    docker push "rfhs/${DISTRO}:${VERS}"
    docker push "rfhs/${DISTRO}:latest"
  fi
  exit_code=0
else
  printf "rfhs_checker failed!\n"
  # the container is removed when it stops, so show its logs now
  docker logs --tail 200 "${CONTAINER_NAME}" || true
  exit_code=1
fi
docker stop "${CONTAINER_NAME}"
sudo modprobe -r mac80211_hwsim
exit "${exit_code}"
