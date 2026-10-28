#!/bin/sh
set -e
set -u

HOSTNAME="${COLLECTD_HOSTNAME:-$(hostname)}"
INTERVAL="60"

health_check(){
  for container in $(docker ps --format "{{.Names}}"); do
    health="$(docker inspect --format "{{.State.Health.Status}}" "${container}")"
    if [ "${health}" = 'healthy' ]; then
      printf 'PUTVAL "%s/%s/healthy" interval=%s N:%s\n' "${HOSTNAME}" "${container}" "${INTERVAL}" "1"
    else
      printf 'PUTVAL "%s/%s/healthy" interval=%s N:%s\n' "${HOSTNAME}" "${container}" "${INTERVAL}" "0"
    fi
  done
}

awake_since="$(date +%s)"
while true; do

  health_check

  wakeup_time=$(( awake_since + INTERVAL ))
  sleepy_tyme=$(( wakeup_time - $(date +%s) ))
  if [ "${sleepy_tyme}" -gt '0' ] && [ "${sleepy_tyme}" -lt "${INTERVAL}" ]; then
    sleep "${sleepy_tyme}"
  else
    sleep "${INTERVAL}"
  fi
  awake_since="$(date +%s)"
done
