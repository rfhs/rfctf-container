#!/bin/sh
set -x
cloud-init schema --system --annotate
if [ ! -r "/etc/rfctf-contestant" ]; then
  printf '/etc/rfctf-contestant should contain key data but the file is missing\n'
  exit 1
fi
if [ "$(awk -F'=' '{print $2}' /etc/rfctf-contestant | wc -l)" -lt 3 ];
  printf '/etc/rfctf-contestant should contain key data but some data is missing\n'
  exit 1
fi
if [ ! -r '/var/cache/rfhs-rfctf/key/authorized_keys' ]; then
  printf 'No authorized_keys detected, provisioning failed\n'
  exit 1
fi
/etc/init.d/containerd status
/etc/init.d/docker status
cloud-init status
while docker ps | grep -q '(health: starting)'; do
  printf 'docker containers are still starting...\n'
  sleep 30
done
if [ "$(docker ps | wc -l)" -lt "8" ]; then
  printf 'FATAL: Not all docker containers started\n'
  docker ps
  exit 1
fi
if [ "$(docker ps | grep -c '(healthy)')" -lt "5" ]; then
  printf 'FATAL: Not all docker containers are healthy\n'
  docker ps
  exit 1
fi
