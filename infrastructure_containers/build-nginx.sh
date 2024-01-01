#!/bin/sh


Testing=0

TOKEN=$(curl -s -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" "http://169.254.169.254/latest/api/token")
# Extract information about the Instance
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: ${TOKEN}" -s http://169.254.169.254/latest/meta-data/instance-id/)
AZ=$(curl -H "X-aws-ec2-metadata-token: ${TOKEN}" -s http://169.254.169.254/latest/meta-data/placement/availability-zone/)
HOSTNAME=$(aws ec2 describe-tags --region "${AZ::-1}" --filters "Name=resource-id,Values=${INSTANCE_ID}" --query 'Tags[?Key==`Name`].Value' --output text)

#HOSTNAME=$(hostname)
#HOSTNAME=fmathyoucantuse-kumaragururft.contestant.irregulartech.com
EMAIL=rfarina@rfhackers.com

/bin/sed -i "s/server_name.*/server_name $HOSTNAME;/" files/nginx.conf
/bin/sed -i "s/server_name.*/server_name $HOSTNAME;/" files/sslnginx.conf

echo "<HTML><meta http-equiv="Content-Language" content="en"><BODY><a href="https://$HOSTNAME:8443/vnc.html">Open Pentoo</a><br><a href="https://$HOSTNAME:8444/vnc.html">Open Kali Linux</a><br><a href="https://$HOSTNAME:8445/vnc.html">Open Parrot</a><br><a href="https://$HOSTNAME:8446/vnc.html">Open Blackarch</a></BODY></HTML>" > files/index.html

docker build -t rfhs/nginx -f Dockerfile.nginx .

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
