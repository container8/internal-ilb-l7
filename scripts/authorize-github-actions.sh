#!/usr/bin/env bash
set -euo pipefail

# This needs to be setup once per repository (each repo should have its' own provider)
# Docs: https://github.com/google-github-actions/auth?tab=readme-ov-file#preferred-direct-workload-identity-federation

# Include secrets
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -e "${SCRIPT_DIR}/../.env" ]; then
    source ${SCRIPT_DIR}/../.env
fi

export PROJECT_ID=ilb-l7-gke-poc
export LOCATION=global
export GITHUB_ORG=container8
export WORKLOAD_IDENTITY_POOL_ID=projects/486512027028/locations/global/workloadIdentityPools/github
export REPO=container8/gcp-infra

# gcloud iam workload-identity-pools list --location $LOCATION --project ${PROJECT_ID}
gcloud iam workload-identity-pools create "github" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# projects/486512027028/locations/global/workloadIdentityPools/github
gcloud iam workload-identity-pools describe "github" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --format="value(name)"

gcloud iam workload-identity-pools providers create-oidc "github-gcp-infra" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="github" \
  --display-name="GCP-Infra GitHub Repo Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner == '${GITHUB_ORG}'" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# projects/486512027028/locations/global/workloadIdentityPools/github/providers/github-gcp-infra
gcloud iam workload-identity-pools providers describe "github-gcp-infra" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="github" \
  --format="value(name)"

# grant full access to the project 
# gcloud projects get-iam-policy ${PROJECT_ID}
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --role="roles/owner" \
  --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${REPO}"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="user:ivan.ermilov@xalt.de" \
  --role="roles/storage.admin"
