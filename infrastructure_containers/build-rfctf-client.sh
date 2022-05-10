#!/bin/sh
set -e
VERS="1.0"
DISTRO="rfctf-client"
docker build . --pull -f "Dockerfile.${DISTRO}" -t rfhs/${DISTRO}:${VERS}
docker tag rfhs/${DISTRO}:${VERS} rfhs/${DISTRO}:latest
if [ "$(hostname)" = "Nu" ] ; then
  docker push rfhs/${DISTRO}
  docker push rfhs/${DISTRO}:latest
fi
