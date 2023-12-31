#!/bin/sh


Testing=1

TOKEN=$(curl -s -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" "http://169.254.169.254/latest/api/token")
# Extract information about the Instance
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: ${TOKEN}" -s http://169.254.169.254/latest/meta-data/instance-id/)
AZ=$(curl -H "X-aws-ec2-metadata-token: ${TOKEN}" -s http://169.254.169.254/latest/meta-data/placement/availability-zone/)
HOSTNAME=$(aws ec2 describe-tags --region "${AZ::-1}" --filters "Name=resource-id,Values=${INSTANCE_ID}" --query 'Tags[?Key==`Name`].Value' --output text)

#HOSTNAME=$(hostname)
#HOSTNAME=fmathyoucantuse-kumaragururft.contestant.irregulartech.com
EMAIL=rfarina@rfhackers.com

docker run -d --rm --userns host --network host --name "rfhs-nginx" "rfhs/nginx"

if [[ $Testing -eq 1 ]]; then
  #test commands only
  docker exec -it rfhs-nginx certbot certonly --agree-tos --email $EMAIL -n --cert-name rfhscontestant --nginx -d $HOSTNAME --test-cert
  docker cp certs.tar rfhs-nginx:certs.tar
  docker exec rfhs-nginx tar -xf /certs.tar -C /etc/letsencrypt/live/rfhscontestant/
  #end test commands
else
  docker exec -it rfhs-nginx certbot certonly --agree-tos --email $EMAIL -n --cert-name rfhscontestant --nginx -d $HOSTNAME
fi

docker cp files/sslnginx.conf rfhs-nginx:/etc/nginx/conf.d/sslnginx.conf
docker exec -d rfhs-nginx /etc/init.d/nginx reload
