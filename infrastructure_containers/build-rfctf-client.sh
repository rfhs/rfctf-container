#!/bin/sh
set -eu
VERS="1.0"
DISTRO="rfctf-client"
docker build . --pull -f "Dockerfile.${DISTRO}" -t rfhs/${DISTRO}:${VERS}

## You know what all the cool kids like?  CI!  Time to test like a boss
# This is probably unsafe AND requires root.  I'd rather CI than no CI though, so for now it's happening
# This is unsafe in the following ways:
# The hwsim devices have to be 0-3, but if there are other wifi cards they won't be
# This just modprobes and rips out the module, needed or otherwise, which means it's not parallel safe at all

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
if [ -n "$(docker ps -a -q)" ]; then
  docker rm $(docker ps -a -q)
fi

# Get a list of the radios (a little safer than assuming)
#CONTAINER_PHYS="$(sudo airmon-ng | awk '/mac80211_hwsim/ {print $1}')"
CONTAINER_PHYS="phy10 phy11 phy12 phy13 phy14 phy15 phy16 phy17 phy18 phy19 phy20 phy21 phy22 phy23 phy24 phy25"
# Start the container
docker run -d --rm --network none --name "${CONTAINER_NAME}" \
  --cap-add net_raw --cap-add net_admin \
  "rfhs/${DISTRO}:${VERS}"
  #--privileged --userns host \
# Give it radios
clientpid=$(docker inspect --format "{{ .State.Pid }}" "${CONTAINER_NAME}")
for phy in ${CONTAINER_PHYS}; do
  while true; do
    if iw phy "${phy}" info > /dev/null 2>&1; then
      printf "Found %s, moving it into %s\n" "${phy}" "${CONTAINER_NAME}"
      break
    fi
    printf "Unable to find %s, waiting...\n" "${phy}"
    sleep 1
  done
  sudo iw phy "${phy}" set netns "${clientpid}"
done
sleep 90
if docker exec -it "${CONTAINER_NAME}" './ldm_checker --test'; then
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
