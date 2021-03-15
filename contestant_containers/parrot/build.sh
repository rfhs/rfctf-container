#!/bin/sh
VERS="0.10"
docker build . -t rfhs/parrot:${VERS}
docker tag rfhs/parrot:${VERS} rfhs/parrot:latest
#docker push rfhs/parrot
