#!/bin/sh
VERS="0.12"
#CAP_SYS_ADMIN CAP_NET_ADMIN ?
docker build . -t rfhs/pentoo:${VERS}
docker tag rfhs/pentoo:${VERS} rfhs/pentoo:latest
#docker push rfhs/pentoo
