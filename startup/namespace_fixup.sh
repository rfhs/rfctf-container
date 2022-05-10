#!/bin/bash -x

set -eu -o pipefail

if [ -n "$(command -v id 2> /dev/null)" ]; then
  USERID="$(id -u 2> /dev/null)"
fi

if [ -z "${USERID}" ] && [ -n "$(id -ru)" ]; then
  USERID="$(id -ru)"
fi

if [ -n "${USERID}" ] && [ "${USERID}" != "0" ]; then
  printf "Run it as root\n" ; exit 1;
elif [ -z "${USERID}" ]; then
  printf "Unable to determine user id, permission errors may occur.\n"
fi

#CONTAINER_NAME="${1:-}"

if [[ $EUID -ne 0 ]]; then
  echo -e "You *did* plan on mutating namespace configurations, right...?\n"

  echo "This script must be run as root" 
  exit 1
fi

function create_ns_link {
  local PID=$(docker inspect -f '{{.State.Pid}}' ${CONTAINER_NAME})

  if [ -z "${PID}" ]; then
    echo "Unable to identify process id for ${CONTAINER_NAME}, skipping."
    exit
  fi
  mkdir -p /run/netns/
  touch "/run/netns/${CONTAINER_NAME}"
  echo "Mapping namespaces of process id ${PID} for ${CONTAINER_NAME} to namespace name ${CONTAINER_NAME}"
  mount -o bind "/proc/${PID}/ns/net" "/run/netns/${CONTAINER_NAME}"
}

if [ -z "$*" ]; then
  #       CONTAINERS="openwrt wctf-client contestant"
  CONTAINERS="$(docker ps --format '{{ .Names }}')"
else
  CONTAINERS="$*"
fi

#for CONTAINER in "openwrt" "wctf-client" "contestant"; do
for CONTAINER in ${CONTAINERS}; do
  CONTAINER_NAME="${CONTAINER}"
  create_ns_link
done
