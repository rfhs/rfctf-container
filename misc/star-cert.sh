#!/bin/sh

set -eu

WEBROOT='/var/cache/rfhs-rfctf/www'
CERTBOT_CONFDIR='/var/cache/rfhs-rfctf/ssl'

docker run -it --rm --name rhfs-certbot \
  -v "${WEBROOT}":/var/www/rfhscontestant/:rw \
  -v "${CERTBOT_CONFDIR}":/etc/letsencrypt/:rw \
  certbot/certbot:latest \
  certonly --manual \
  --preferred-challenges=dns \
  --email rfarina@rfhackers.com \
  --agree-tos \
  --manual-public-ip-logging-ok \
  -d "*.contestant.rfhackers.com" \
  --cert-name rfhscontestant
