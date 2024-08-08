#!/usr/bin/env bash
set -euo pipefail

# Include secrets
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -e "${SCRIPT_DIR}/../.env" ]; then
    source ${SCRIPT_DIR}/../.env
fi

docker run -it --rm --name certbot \
    -v "${SCRIPT_DIR}:/scripts" \
    -v "${SCRIPT_DIR}/../secrets/certs/etc/letsencrypt:/etc/letsencrypt" \
    -v "${SCRIPT_DIR}/../secrets/certs/var/lib/letsencrypt:/var/lib/letsencrypt" \
    -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
    -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
    --entrypoint /bin/sh \
    certbot/certbot -c /scripts/provision-certs-certbot.sh
