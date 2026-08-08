#!/bin/sh
set -eu
if [ "$(date -r portage_and_overlay.tar.xz +%s)" -lt "$(date -d "7 days ago" +%s)" ]; then
  printf "portage_and_overlay.tar.xz is too old, aborting for safety\n"
  exit 1
fi
VERS="1.3"
DISTRO="rfctf-sdr"
docker pull docker.io/pentoolinux/pentoo-core
docker build --no-cache . --progress=plain -f "Dockerfile.${DISTRO}" -t rfhs/${DISTRO}:${VERS}
docker tag rfhs/${DISTRO}:${VERS} rfhs/${DISTRO}:latest
if docker run --rm --network none --name "rfhs-${DISTRO}-ci" rfhs/${DISTRO} ./challengectl.py --test --flagfile flags.txt.ci --devicefile devices.txt.ci; then
  if [ "$(hostname)" = "Nu" ] || [ "$(hostname)" = "naga" ]; then
    docker push rfhs/${DISTRO}
    docker push rfhs/${DISTRO}:${VERS}
    docker push rfhs/${DISTRO}:latest
  fi
  exit_code=0
else
  exit_code=1
fi
exit ${exit_code}
