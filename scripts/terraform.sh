#!/usr/bin/env bash
# set -euo pipefail

command=$1

# Include secrets
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -e "${SCRIPT_DIR}/../.env" ]; then
    source ${SCRIPT_DIR}/../.env
fi

echo "Running terraform on the branch: ${intranet_branch}"

export GITHUB_WORKSPACE=${GITHUB_WORKSPACE:-"${SCRIPT_DIR}/.."}
export TF_PLAN_PATH=${3:-"${GITHUB_WORKSPACE}/plan.tfplan"}
export TERRAFORM_STATE_KEY=github-gcp-infra-main
export ENV=main
export ENV_PATH=${SCRIPT_DIR}/../env

terraform fmt -check -diff
echo "Terraform key is set to: ${TERRAFORM_STATE_KEY}"
terraform -chdir=${SCRIPT_DIR}/../terraform init -upgrade -reconfigure -backend-config="prefix=${TERRAFORM_STATE_KEY}" -input=false

case ${command} in
    validate)
        echo "Running terraform validate"
        terraform validate
        ;;
    plan)
        echo "Running terraform plan"
        echo "terraform -chdir=${SCRIPT_DIR}/../terraform plan -out=${TF_PLAN_PATH} -input=false --var-file=${ENV_PATH}/${ENV}.tfvars"
        terraform -chdir=${SCRIPT_DIR}/../terraform plan -out=${TF_PLAN_PATH} -input=false --var-file=${ENV_PATH}/${ENV}.tfvars
        ;;
    plan-destroy)
        echo "Running terraform plan -destroy"
        echo "terraform -chdir=${SCRIPT_DIR}/../terraform plan -destroy -out=${TF_PLAN_PATH} -input=false --var-file=${ENV_PATH}/${ENV}.tfvars"
        terraform -chdir=${SCRIPT_DIR}/../terraform plan -destroy -out=${TF_PLAN_PATH} -input=false --var-file=${ENV_PATH}/${ENV}.tfvars
        ;;
    apply)
        echo "Running terraform apply"
        echo "terraform -chdir=${SCRIPT_DIR}/../terraform apply -auto-approve ${TF_PLAN_PATH}"
        terraform -chdir=${SCRIPT_DIR}/../terraform apply -auto-approve ${TF_PLAN_PATH}
        ;;
    *)
        echo "${command} is not defined, exiting"
        exit 1
        ;;
esac
