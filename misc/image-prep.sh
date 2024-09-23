#!/bin/sh
# This script is used before creating the game image to clean up the master

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

# pull latest images for everything, after cleaning up to ensure there is space
for image in $(docker image ls | grep '^rfhs' | awk '{print $1}') 'certbot/certbot' nginx; do
  docker image prune --force
  docker pull "${image}"
  docker image prune --force
done

docker system prune --volumes --force

if ! docker run --rm --name rfhs-certbox -v /var/cache/rfhs-rfctf/www:/var/www/rfhscontestant/:rw -v /var/cache/rfhs-rfctf/ssl:/etc/letsencrypt/:rw certbot/certbot:latest certificates 2> /dev/null | grep 'VALID'; then
  printf "Certs are no longer valid! Please manually renew certs\n"
  exit 1
fi

# clean cloud init
# always run this LAST
[ -x "$(command -v cloud-init 2>&1)" ] && cloud-init clean
