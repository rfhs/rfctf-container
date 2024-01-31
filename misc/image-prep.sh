#!/bin/sh
# This script is used before creating the game image to clean up the master

# stop all running docker containers
if [ -n "$(docker ps -a -q)" ]; then
  # shellcheck disable=2046
  docker stop $(docker ps -a -q)
fi

docker system prune --volumes --force

# pull latest images for everything
for image in $(docker image ls | grep '^rfhs' | awk '{print $1}'); do
  docker image prune --force
  docker pull "${image}"
  docker image prune --force
done

# cleanup unneeded gentoo files leftover from upgrading
if [ -x "$(command -v portageq 2>&1)" ]; then
  if [ -d "$(portageq envvar DISTDIR)" ]; then
    # protected above
    # shellcheck disable=2115
    rm -rf "$(portageq envvar DISTDIR)"/*
  fi
  if [ -d "$(portage envvar PKGDIR)" ]; then
    # protected above
    # shellcheck disable=2115
    rm -rf "$(portageq envvar PKGDIR)"/*
  fi
  rm -rf "$(portageq envvar PORTAGE_TMPDIR)"/portage/*
fi

# ensure shared-persistent_storage is empty
if [ -d '/var/cache/rfhs-rfctf/shared_persistent_storage/*' ]; then
  rm -rf /var/cache/rfhs-rfctf/shared_persistent_storage/*
fi

# wipe all the container logs
if [ -d '/var/log/rfhs-rfctf' ]; then
  find /var/log/rfhs-rfctf/ -type f -not -name authorized_keys -exec rm -rf {} \;
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

# Check if old kernels are still there
if [ "$(find /usr/src/ -mindepth 1 -maxdepth 1 -type d | wc -l)" -gt 1 ]; then
  printf 'Found more than one set of kernel sources, please manually clean them up before snapshotting.\n'
  exit 1
fi

# clean cloud init
[ -x "$(command -v cloud-init 2>&1)" ] && cloud-init clean
