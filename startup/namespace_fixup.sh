#!/bin/sh

set -eu

DEBUG="${DEBUG:-}"

if [ -n "${DEBUG}" ]; then
  set -x
fi

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

create_ns_link() {
  PID="$(docker inspect -f '{{.State.Pid}}' "${CONTAINER_NAME}")"

  if [ -z "${PID}" ]; then
    printf "Unable to identify process id for %s, skipping.\n" "${CONTAINER_NAME}"
    exit 1
  fi
  mkdir -p /run/netns/
  touch "/run/netns/${CONTAINER_NAME}"
  printf "Mapping namespaces of process id %s for %s to namespace name %s" "${PID}" "${CONTAINER_NAME}" "${CONTAINER_NAME}"
  mount -o bind "/proc/${PID}/ns/net" "/run/netns/${CONTAINER_NAME}"
}

if [ -z "$*" ]; then
  CONTAINERS="$(docker ps --format '{{ .Names }}')"
else
  CONTAINERS="$*"
fi

for CONTAINER in ${CONTAINERS}; do
  CONTAINER_NAME="${CONTAINER}"
  create_ns_link
done
