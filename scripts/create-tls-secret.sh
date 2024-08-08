#!/usr/bin/env bash
set -euo pipefail

# Include secrets
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -e "${SCRIPT_DIR}/../.env" ]; then
    source ${SCRIPT_DIR}/../.env
fi

DEPLOYMENT_NAME=foo
CERTS_PATH=secrets/certs/etc/letsencrypt/live/${DEPLOYMENT_NAME}.xalt.team

kubectl -n argocd create secret tls ${DEPLOYMENT_NAME}-tls --cert=${SCRIPT_DIR}/../${CERTS_PATH}/fullchain.pem --key=${SCRIPT_DIR}/../${CERTS_PATH}/privkey.pem
