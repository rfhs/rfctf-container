#!/bin/sh
VERS="0.2"
docker build . -t rfhs/client_server:${VERS}
docker tag rfhs/client_server:${VERS} rfhs/client_server:latest
#docker push rfhs/client_server
#docker push rfhs/client_server:latest
