#!/bin/sh
VERS="0.1"
#CAP_SYS_ADMIN CAP_NET_ADMIN ?
docker build . --pull -t rfhs/client_server:${VERS}
docker tag rfhs/client_server:${VERS} rfhs/client_server:latest
#docker push rfhs/client_server
#docker push rfhs/client_server:latest
