# GCP: cross-region ILB Infra Repository

Example of routing internal traffic in GCP using cross-region ILB to k8s clusters in 2 regions.
Utilizes autoneg controller from the google cloud team.

What is implemented in this demo:
- Cross Regional ILB L7 deployment (backend-service)
- Autoneg controller deployment to register NEGs automatically in backend-service

TODOs:
- Urlmap configuration for location aware traffic

## Requirements

Use [ark](https://github.com/alexellis/arkade) to install the requirements:

* gcloud
* terraform
* kubectl
* [gke-gcloud-auth-plugin](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin)

## Local Development

```
# search and replace ilb-l7-gke-poc in the other files as
PROJECT=ilb-l7-gke-poc
gcloud auth login
gcloud config set project ${PROJECT}
gcloud auth application-default login

gcloud services enable \
  trafficdirector.googleapis.com \
  multiclusterservicediscovery.googleapis.com \
  multiclusteringress.googleapis.com \
  --project=${PROJECT}

./scripts/create-bucket.sh

./scripts/terraform.sh init
./scripts/terraform.sh plan
./scripts/terraform.sh apply
# takes around 20 mins to deploy
```

## Deploy Nginx Application

```
# Install gke-autoneg-controller
cd .. && git clone git@github.com:GoogleCloudPlatform/gke-autoneg-controller.git && cd internal-ilb-l7-poc

# Deploy Workload Identity
export PROJECT_ID=ilb-l7-gke-poc
../gke-autoneg-controller/deploy/workload_identity.sh

gcloud container clusters get-credentials cluster-belgium --region us-east1
kubectl apply -f ../gke-autoneg-controller/deploy/autoneg.yaml
kubectl annotate sa -n autoneg-system autoneg-controller-manager \
  iam.gke.io/gcp-service-account=autoneg-system@${PROJECT_ID}.iam.gserviceaccount.com
k -n autoneg-system delete po <TAB>
k apply -f app/nginx.yaml

gcloud container clusters get-credentials cluster-germany --region us-central1
kubectl apply -f ../gke-autoneg-controller/deploy/autoneg.yaml
kubectl annotate sa -n autoneg-system autoneg-controller-manager \
  iam.gke.io/gcp-service-account=autoneg-system@${PROJECT_ID}.iam.gserviceaccount.com
k apply -f app/nginx.yaml
```

## ArgoCD Connection

```
# Get IP address

# Get pass
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
