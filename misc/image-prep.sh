#!/bin/sh
# This script is used before creating the game image to clean up the master

set -e

check_disk_usage() {
  used="$(df -h / --output=pcent | tail -n1 | awk -F'%' '{gsub(/ /, "", $0); print $1}')"
  if [ "${used}" -gt '80' ]; then
    printf 'FATAL: Disk is too full, disk must be below 80% and is currently %s%%\n' "${used}"
    exit 1
  else
    printf 'INFO: Used disk space is %s%%\n' "${used}"
  fi
}

# stop all running docker containers
if [ -n "$(docker ps -a -q)" ]; then
  # shellcheck disable=2046
  docker stop $(docker ps -a -q)
fi

docker system prune --volumes --force

# cleanup unneeded gentoo files leftover from upgrading
if [ -x "$(command -v portageq 2>&1)" ]; then
  DISTDIR="$(portageq envvar DISTDIR)"
  if [ -d "${DISTDIR}" ]; then
    rm -rf "${DISTDIR:?}"/*
  fi
  PKGDIR="$(portageq envvar PKGDIR)"
  if [ -d "${PKGDIR}" ]; then
    rm -rf "${PKGDIR:?}"/*
  fi
  rm -rf "$(portageq envvar PORTAGE_TMPDIR)"/portage/*
fi

# cleanup some undesired logs
for i in cloud-init.log cloud-init-output.log amazon/amazon-cloudwatch-agent/amazon-cloudwatch-agent.log portage/elog/summary.logi emerge.log rc.log docker.log containerd/containerd.log; do
  if [ -e "/var/log/${i}" ]; then
    truncate -s0 "/var/log/${i}"
  fi
done

# ensure shared-persistent_storage is empty
if [ -d '/var/cache/rfhs-rfctf/shared_persistent_storage/' ]; then
  rm -rf /var/cache/rfhs-rfctf/shared_persistent_storage/*
fi

# Ensure the key location exists and has correct perms
if [ ! -d '/var/cache/rfhs-rfctf/key' ]; then
  mkdir -p '/var/cache/rfhs-rfctf/key'
fi

# wipe all the container logs
if [ -d '/var/log/rfhs-rfctf' ]; then
  rm -rf /var/log/rfhs-rfctf/*
fi

# wipe nginx/certbot stuff
if [ -d '/var/cache/rfhs-rfctf/nginx' ]; then
  rm -rf /var/cache/rfhs-rfctf/nginx/*
fi
if [ -d '/var/cache/rfhs-rfctf/www' ]; then
  rm -rf /var/cache/rfhs-rfctf/www/*
fi
## We are using a star cert while waiting for approval for more requests
#if [ -d '/var/cache/rfhs-rfctf/ssl' ]; then
#  rm -rf /var/cache/rfhs-rfctf/ssl/*
#fi
## We check if the star cert is valid after the docker pulls so we can see the output easier

# Check if old kernels are still there
if [ "$(find /usr/src/ -mindepth 1 -maxdepth 1 -type d | wc -l)" -gt 1 ]; then
  printf 'Found more than one set of kernel sources, please manually clean them up before snapshotting.\n'
  exit 1
fi
if [ "$(find /lib/modules -mindepth 1 -maxdepth 1 -type d | wc -l)" -gt 1 ]; then
  printf 'Found more than one set of kernel modules, please manually clean them up before snapshotting.\n'
  exit 1
fi

check_disk_usage

# pull latest images for everything, after cleaning up to ensure there is space
for image in $(docker image ls | grep '^rfhs' | awk '{print $1}') 'certbot/certbot' nginx; do
  docker image prune --force
  docker pull "${image}"
  docker image prune --force
done

docker system prune --volumes --force

printf -- '\n\n--------------------------------------------------------------------------------\n'
if ! docker run --rm --name rfhs-certbox -v /var/cache/rfhs-rfctf/www:/var/www/rfhscontestant/:rw -v /var/cache/rfhs-rfctf/ssl:/etc/letsencrypt/:rw certbot/certbot:latest certificates 2> /dev/null | grep 'VALID'; then
  printf 'Certs are no longer valid! Please manually renew certs\n'
  exit 1
fi

check_disk_usage

# clean cloud init
# always run this LAST
if [ -x "$(command -v cloud-init 2>&1)" ]; then
  #printf 'Running `cloud-init clean` ...\n'
  if cloud-init clean > /dev/null 2>&1; then
    #printf 'cloud-init clean successful\n'
    true
  else
    #re-run to see the error
    cloud-init clean
    printf 'cloud-init clean failed\n'
    exit 1
  fi
  if [ "$(cloud-init status)" = "status: not run" ]; then
    #printf 'cloud-init status "not run", safe to continue\n'
    true
  else
    printf 'cloud-init clean worked but status is wrong\n'
    exit 1
  fi
else
  printf 'cloud-init was not found, if you expected it to be found this is a problem.\n'
fi

printf '%s ran successfully\n' "${0}"
printf 'Ready for imaging.\n'
