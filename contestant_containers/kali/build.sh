#!/bin/sh
VERS="0.10"
docker build . -t rfhs/kali:${VERS}
docker tag rfhs/kali:${VERS} rfhs/kali:latest
#docker push rfhs/kali
