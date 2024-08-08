#!/usr/bin/env bash
set -euo pipefail

# Include secrets
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -e "${SCRIPT_DIR}/../.env" ]; then
    source ${SCRIPT_DIR}/../.env
fi

# Define the bucket name and location
BUCKET_NAME="tf-state-ilb-l7-gke-poc"
LOCATION="europe-west1"

# Check if the bucket exists
if ! gsutil ls -b gs://$BUCKET_NAME > /dev/null 2>&1; then
  # Create the bucket if it doesn't exist
  gcloud storage buckets create gs://$BUCKET_NAME --location=$LOCATION
  gsutil uniformbucketlevelaccess set on gs://$BUCKET_NAME
  echo "Bucket $BUCKET_NAME created."
else
  echo "Bucket $BUCKET_NAME already exists."
fi
