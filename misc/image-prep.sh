#!/bin/sh
# This script is used before creating the game image to clean up the master

cleanup_docker() {
  # cleanup untagged docker images
  if [ -n "$(docker images | grep "<none>" | awk '{print $3}')" ]; then
    docker rmi $(docker images | grep "<none>" | awk '{print $3}')
  fi
}

# stop all running docker containers
if [ -n "$(docker ps -a -q)" ]; then
  docker stop $(docker ps -a -q)
fi
# remove any stopped containers which weren't removed already
if [ -n "$(docker ps -a -q)" ]; then
  docker rm $(docker ps -a -q)
fi

# pull latest images for everything
for image in $(docker image ls | grep '^rfhs' | awk '{print $1}'); do
  cleanup_docker
  docker pull "${image}"
  cleanup_docker
done

# cleanup unneeded gentoo files leftover from upgrading
if [ -x "$(command -v portageq 2>&1)" ]; then
  rm -rf "$(portageq envvar DISTDIR)"/*
  rm -rf "$(portageq envvar PKGDIR)"/*
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

# clean cloud init
[ -x "$(command -v cloud-init 2>&1)" ] && cloud-init clean
