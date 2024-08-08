#!/usr/bin/env sh
# certbot container only support plain sh

# This file should be run inside certbot container, see provision-certs.sh script
# For each domain we need one certification with e.g. aska.bot and *.aska.bot SANs
DOMAIN_LIST="foo.xalt.team"

pip3 install certbot certbot-dns-route53

for domain in ${DOMAIN_LIST}
do
    echo "Renewing $domain and *.${domain} certificate"
    certbot certonly -n \
        --dns-route53 \
        -m ivan.ermilov@xalt.de \
        --agree-tos --no-eff-email \
        -d *.${domain},${domain}
done
