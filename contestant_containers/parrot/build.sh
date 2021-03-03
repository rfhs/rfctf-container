#!/bin/sh
VERS="0.9"
docker build . -t rfhs/parrot:${VERS}
docker tag rfhs/parrot:${VERS} rfhs/parrot:latest
#docker push rfhs/parrot
