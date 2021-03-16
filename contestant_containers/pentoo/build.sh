#!/bin/sh
VERS="0.12"
docker build . -t rfhs/pentoo:${VERS}
docker tag rfhs/pentoo:${VERS} rfhs/pentoo:latest
#docker push rfhs/pentoo
