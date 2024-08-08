#!/usr/bin/env bash
# set -euo pipefail

# Include secrets
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -e "${SCRIPT_DIR}/../.env" ]; then
    source ${SCRIPT_DIR}/../.env
fi

CLUSTER_NAME=autopilot-cluster
REGION=europe-west2

gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION}
kubectl create ns argocd || echo "already exist"
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd --values ${SCRIPT_DIR}/../argocd/values.yml --namespace argocd argo/argo-cd
