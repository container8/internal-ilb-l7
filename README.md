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
# The NEGs are created from inside GKE and not available as data sources on the first TF run
# Clusters should be created separate from the load balancer configuration to enable stream lined disaster recovery
```

## Deploy Nginx Application

```
# Install gke-autoneg-controller
cd .. && git clone git@github.com:GoogleCloudPlatform/gke-autoneg-controller.git && cd internal-ilb-l7-poc

# Deploy Workload Identity
export PROJECT_ID=ilb-l7-gke-poc
../gke-autoneg-controller/deploy/workload_identity.sh

# Optional AutoNEG Installation
kubectl apply -f ../gke-autoneg-controller/deploy/autoneg.yaml
kubectl annotate sa -n autoneg-system autoneg-controller-manager \
  iam.gke.io/gcp-service-account=autoneg-system@${PROJECT_ID}.iam.gserviceaccount.com
k -n autoneg-system delete po <TAB>

# Setup cluster contexts
gcloud container clusters get-credentials cluster-germany --region us-central1
gcloud container clusters get-credentials cluster-belgium --region us-east1

# Edit .kube/config and rename contexts to germany/belgium
kubectx belgium
k apply -f app/nginx-belgium.yaml

kubectx germany
k apply -f app/nginx-germany.yaml

# Check NEGs
gcloud compute network-endpoint-groups list

# Uncomment predefined NEGs / dynamic backends and run terraform apply
./scripts/terraform.sh plan
./scripts/terraform.sh apply

# Get ILB IP Address
gcloud compute forwarding-rules list --global # 10.128.0.100

# Connect to the test VM
gcloud compute ssh debian-vm --zone=us-central1-a

# Test connection to ILB
sudo apt-get update && sudo apt-get install netcat-openbsd
nc -z -v 10.128.0.100 80
Connection to 10.128.0.100 80 port [tcp/http] succeeded!

# Add to /etc/hosts
# 10.128.0.100 dev.example.com

# Send request to the dev.example.com
curl -s http://dev.example.com | grep -i server
curl -s -H "X-Country: Germany" http://dev.example.com | grep -i server
curl -s -H "X-Country: Belgium" http://dev.example.com | grep -i server

# Scale deployment to 0 - emulate service failure
kubectl scale --replicas=0 deployment/nginx-deployment

curl -H "X-Country: Germany" http://dev.example.com
# no healthy upstream

```

Other commands:

```
gcloud compute networks subnets list

# Delete URLMap / Forwarding rule
gcloud compute forwarding-rules delete test
gcloud compute target-http-proxies delete gil7-map-target-proxy
gcloud compute url-maps delete gil7-map

# Clean up NEGs
gcloud compute network-endpoint-groups list
gcloud compute network-endpoint-groups delete nginx-neg-germany --zone us-central1-a
gcloud compute network-endpoint-groups delete nginx-neg-germany --zone us-central1-c
gcloud compute network-endpoint-groups delete nginx-neg-germany --zone us-central1-f
gcloud compute network-endpoint-groups delete nginx-neg-belgium --zone us-east1-b
gcloud compute network-endpoint-groups delete nginx-neg-belgium --zone us-east1-c
gcloud compute network-endpoint-groups delete nginx-neg-belgium --zone us-east1-d

# Allow SSH to the VM
gcloud compute instances describe debian-vm

gcloud compute firewall-rules list
gcloud compute firewall-rules create allow_ssh_germany \
    --action=ALLOW \
    --direction=INGRESS \
    --network=gke-vpc \
    --priority=1000 \
    --rules=tcp:22 \
    --source-ranges=0.0.0.0/0

# Check health checks
gcloud compute backend-services get-health backend-service-belgium --global
gcloud compute backend-services get-health backend-service-germany --global
gcloud compute backend-services get-health backend-service-europe --global

# Try - Cross-region internal proxy Network Load Balancer
# https://cloud.google.com/load-balancing/docs/tcp/internal-proxy

```

# TCP Traffic Path

## Debugging

```
# Check backend service
gcloud compute backend-services get-health backend-service-europe-tcp --global
```

Traffic paths:

VM --> TCP LB --> Backend Service (Europe) --> NEGs with Pods (ok!)
VM --> TCP LB --> Backend Service (Europe) --> Hybrid NEGs with Gateway IP Addresses (ok!)

From VM:

```
# Connect to the test VM
gcloud compute ssh debian-vm --zone=us-central1-a

# Test connection to ILB
sudo apt-get update && sudo apt-get install netcat-openbsd
nc -z -v 10.128.0.103 80
Connection to 10.128.0.103 80 port [tcp/https] succeeded!

# Germany Gateway
nc -z -v 10.100.0.10 80

# Belgium Gateway
nc -z -v 10.1.0.10 80

# Add to /etc/hosts
# 10.128.0.103 dev.example.com

# Send request to the dev.example.com
curl -s http://dev.example.com | grep -i server
curl -s -H "X-Country: Germany" http://dev.example.com | grep -i server
curl -s -H "X-Country: Belgium" http://dev.example.com | grep -i server
```

## Gateway API Deployment



gcloud container clusters describe cluster-germany \
  --location=us-central1 \
  --format json

gcloud container clusters describe cluster-belgium \
  --location=us-east1 \
  --format json

## Questions

* Can we point backend service to the IP address / gateway endpoint?


# Notes

* Autoneg controller is not strictly required in this setup, we can use the pre-defined names for NEGs as follows

```
# For Germany
'{"exposed_ports": {"80":{"name": "nginx-neg-germany"}}}'
# For Belgium
'{"exposed_ports": {"80":{"name": "nginx-neg-belgium"}}}'
```

# Generate and Create Global Certificate

```
openssl genpkey -algorithm RSA -out ca-key.pem -aes256
openssl req -x509 -new -nodes -key ca-key.pem -sha256 -days 3650 -out ca-cert.pem
openssl genpkey -algorithm RSA -out server-key.pem
openssl req -new -key server-key.pem -out server.csr
cat <<EOF > san.cnf
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[req_distinguished_name]
CN = dev.example.com  # Replace with your domain

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = dev.example.com  # Replace with your primary domain
DNS.2 = example.com      # Additional domain (add more as needed)
EOF

openssl x509 -req -in server.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out server-cert.pem -days 365 -sha256 -extfile san.cnf -extensions req_ext

openssl x509 -in server-cert.pem -text

# global compute SSL certificate
# 'projects/ilb-l7-gke-poc/global/sslCertificates/global-certificate'. Compute SSL certificates are not supported with global INTERNAL_MANAGED load balancer., invalid
gcloud compute ssl-certificates create global-certificate \
    --certificate=server-cert.pem \
    --private-key=server-key.pem \
    --global

# regional compute SSL certificate
gcloud compute ssl-certificates create regional-certificate \
    --certificate=server-cert.pem \
    --private-key=server-key.pem \
    --region=us-central1

gcloud compute ssl-certificates create regional-certificate \
    --certificate=server-cert.pem \
    --private-key=server-key.pem \
    --region=us-east1

gcloud compute ssl-certificates list

# certificate-manager SSL certificate
gcloud certificate-manager certificates create cert-manager-certificate \
   --certificate-file=server-cert.pem \
   --private-key-file=server-key.pem \
   --scope=all-regions

gcloud certificate-manager certificates list

```
