#!/bin/sh
# This script is used before creating the game image to clean up the master

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
  docker pull "${image}"
done
# cleanup untagged docker images
docker rmi $(docker images | grep "<none>" | awk '{print $3}')

# cleanup unneeded gentoo files leftover from upgrading
rm -rf "$(portageq envvar DISTDIR)"/*
rm -rf "$(portageq envvar PKGDIR)"/*

# ensure shared-persistent_storage is empty
rm -rf /var/wctf/shared_persistent_storage/*

# clean cloud init
cloud-init clean
