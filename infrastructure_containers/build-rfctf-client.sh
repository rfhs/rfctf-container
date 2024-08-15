#!/bin/sh
set -eu
VERS="1.0"
DISTRO="rfctf-client"
docker pull docker.io/pentoolinux/pentoo-core
docker build . --pull -f "Dockerfile.${DISTRO}" -t rfhs/${DISTRO}:${VERS}

## You know what all the cool kids like?  CI!  Time to test like a boss
# This is probably unsafe AND requires root.  I'd rather CI than no CI though, so for now it's happening
# This is unsafe in the following ways:
# The hwsim devices have to be 0-3, but if there are other wifi cards they won't be
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
	rfkill_status="$(sudo rfkill list "${index}" 2>&1)"
	if [ $? != 0 ]; then
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
		rfkill_status="$(sudo rfkill unblock "${index}" 2>&1)"
		if [ $? != 0 ]; then
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

# Start by removing hwsim and then making 4 hwsim devices
CONTAINER_NAME="rfhs-${DISTRO}-ci"
if lsmod | grep -q mac80211_hwsim; then
  sudo modprobe -r mac80211_hwsim
  sleep 5
fi
sudo modprobe mac80211_hwsim radios=26
# stop all running docker containers
if [ -n "$(docker ps -a -q)" ]; then
  docker stop $(docker ps -a -q)
fi
# remove any stopped containers which weren't removed already
#if [ -n "$(docker ps -a -q)" ]; then
#  docker rm $(docker ps -a -q)
#fi

# Get a list of the radios (a little safer than assuming)
#CONTAINER_PHYS="phy10 phy11 phy12 phy13 phy14 phy15 phy16 phy17 phy18 phy19 phy20 phy21 phy22 phy23 phy24 phy25"
CONTAINER_PHYS="$(sudo airmon-ng | awk '/mac80211_hwsim/ {print $1}')"
# Start the container
docker run -d --rm --network none --name "${CONTAINER_NAME}" \
  --cap-add net_raw --cap-add net_admin \
  "rfhs/${DISTRO}:${VERS}"
  #--privileged --userns host \
# Give it radios
create_ns_link
for phy in ${CONTAINER_PHYS}; do
  while true; do
    if iw phy "${phy}" info > /dev/null 2>&1; then
      unset driver
      driver="$(awk -F'=' '{print $2}' "/sys/class/ieee80211/${phy}/device/uevent")"
      if [ 'mac80211_hwsim' = "${driver}" ]; then
        printf "Found %s, moving it into %s\n" "${phy}" "${CONTAINER_NAME}"
        break
      else
        printf "Requested phy is using %s driver instead of the expected mac80211_hwsim.  Failing safe.\n" "${driver}"
        exit 1
      fi
    fi
    printf "Unable to find %s, waiting...\n" "${phy}"
    sleep 1
  done
  rfkill_check "${phy}" || rfkill_unblock "${phy}"
  sleep 1
  sudo iw phy "${phy}" set netns name "${CONTAINER_NAME}"
done
sleep 90
if docker exec "${CONTAINER_NAME}" ./ldm_checker --test; then
  docker tag "rfhs/${DISTRO}:${VERS}" "rfhs/${DISTRO}:latest"
  if [ "$(hostname)" = "Nu" ] ; then
    docker push "rfhs/${DISTRO}:${VERS}"
    docker push "rfhs/${DISTRO}:latest"
  fi
  exit_code=0
else
  printf "rfhs_checker failed!\n"
  exit_code=1
fi
docker stop "${CONTAINER_NAME}"
sudo modprobe -r mac80211_hwsim
exit "${exit_code}"
