#!/bin/sh
set -e
VERS="1.1"
DISTRO="rfctf-sdr"
docker build . --pull -f "Dockerfile.${DISTRO}" -t rfhs/${DISTRO}:${VERS}
docker tag rfhs/${DISTRO}:${VERS} rfhs/${DISTRO}:latest
if docker run --rm --name "rfhs-${DISTRO}-ci" rfhs/${DISTRO} ./challengectl.py --test --flagfile flags.txt.ci --devicefile devices.txt.ci; then
  if [ "$(hostname)" = "Nu" ] ; then
    docker push rfhs/${DISTRO}
    docker push rfhs/${DISTRO}:${VERS}
    docker push rfhs/${DISTRO}:latest
  fi
  exit_code=0
else
  exit_code=1
fi
exit ${exit_code}
