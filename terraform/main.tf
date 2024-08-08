##########
# Locals #
##########

locals {
  germany = "us-central1"
  germany_zone_a = "us-central1-a"
  belgium = "us-east1"
  belgium_zone_a = "us-east1-b"
  max_rate_per_endpoint = 100
}

################
# GKE Clusters #
################
data "google_project" "project" {
  project_id = "ilb-l7-gke-poc"
}

resource "google_service_account" "default" {
  account_id   = "service-account-id"
  display_name = "Service Account"
}

resource "google_container_cluster" "gke_cluster_be" {
  name     = "cluster-belgium"
  location = local.belgium

  # enable_autopilot    = true
  deletion_protection = false

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  initial_node_count = 1
  remove_default_node_pool = true
  workload_identity_config {
    workload_pool = "${data.google_project.project.project_id}.svc.id.goog"
  }

  network    = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.subnetwork_belgium.name

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "default"
    }
  }
}

resource "google_container_node_pool" "gke_cluster_be_nodes" {
  name       = "be-nodes"
  location   = google_container_cluster.gke_cluster_be.location
  cluster    = google_container_cluster.gke_cluster_be.name
  node_count = 1

  node_config {
    disk_size_gb = 20
    machine_type = "e2-medium"

    service_account = google_service_account.default.email
    oauth_scopes    = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}

resource "google_container_cluster" "gke_cluster_de" {
  name     = "cluster-germany"
  location = local.germany

  #enable_autopilot    = true
  deletion_protection = false
  
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  initial_node_count = 1
  remove_default_node_pool = true
  workload_identity_config {
    workload_pool = "${data.google_project.project.project_id}.svc.id.goog"
  }

  network    = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.subnetwork_germany.name

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "default"
    }
  }
}

resource "google_container_node_pool" "gke_cluster_de_nodes" {
  name       = "be-nodes"
  location   = google_container_cluster.gke_cluster_de.location
  cluster    = google_container_cluster.gke_cluster_de.name
  node_count = 1

  node_config {
    disk_size_gb = 20
    machine_type = "e2-medium"

    service_account = google_service_account.default.email
    oauth_scopes    = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}

resource "google_gke_hub_membership" "membership_de" {
  membership_id = "cluster-de"
  location      = "global"
  endpoint {
    gke_cluster {
      resource_link = google_container_cluster.gke_cluster_de.id
    }
  }
}

resource "google_gke_hub_membership" "membership_be" {
  membership_id = "cluster-be"
  location      = "global"
  endpoint {
    gke_cluster {
      resource_link = google_container_cluster.gke_cluster_be.id
    }
  }
}

# resource "google_gke_hub_feature" "multicluster_ingress" {
#   name     = "multiclusteringress"
#   location = "global"
#   spec {
#     multiclusteringress {
#       config_membership = google_gke_hub_membership.membership_de.id
#     }
#   }
# }

####################
# Internal Network #
####################

resource "google_compute_network" "vpc_network" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnetwork_germany" {
  name          = "subnet-germany"
  ip_cidr_range = "10.0.0.0/16"
  network       = google_compute_network.vpc_network.name
  region        = local.germany
}

resource "google_compute_subnetwork" "subnetwork_belgium" {
  name          = "subnet-belgium"
  ip_cidr_range = "10.1.0.0/16"
  network       = google_compute_network.vpc_network.name
  region        = local.belgium
}

resource "google_compute_subnetwork" "subnetwork_vm_germany" {
  name          = "subnetwork-vm-de"
  network       = google_compute_network.vpc_network.self_link
  ip_cidr_range = "10.2.2.0/24"
  region        = local.germany
}

resource "google_compute_subnetwork" "subnetwork_vm_belgium" {
  name          = "subnetwork-vm-be"
  network       = google_compute_network.vpc_network.self_link
  ip_cidr_range = "10.2.3.0/24"
  region        = local.germany
}

###########
# Test VM #
###########

resource "google_compute_instance" "debian_vm" {
  name         = "debian-vm"
  machine_type = "e2-medium"
  zone         = local.germany_zone_a

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.self_link
    subnetwork = google_compute_subnetwork.subnetwork_vm_germany.self_link

    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys = "iermilov:${file(var.ssh_public_key_path)}"
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  tags = ["http-server"]
}

#################
# Load Balancer #
#################

# Already exist? (check)
# This proxy-only subnet is used by all Envoy-based regional load balancers in the same region of the VPC network. There can only be one active proxy-only subnet for a given purpose, per region, per network.
# At any point, only one subnet with purpose GLOBAL_MANAGED_PROXY can be active in each region of a VPC network.
# A proxy-only subnet must provide 64 or more IP addresses (min /26, recommended /23)
# Should be centrally managed for the network

resource "google_compute_subnetwork" "proxy_subnet_germany" {
  name          = "proxy-subnet-de"
  purpose       = "GLOBAL_MANAGED_PROXY"
  role          = "ACTIVE"
  region        = local.germany
  network       = google_compute_network.vpc_network.name
  ip_cidr_range = "10.2.0.0/24"
}

resource "google_compute_subnetwork" "proxy_subnet_belgium" {
  name          = "proxy-subnet-be"
  purpose       = "GLOBAL_MANAGED_PROXY"
  role          = "ACTIVE"
  region        = local.belgium
  network       = google_compute_network.vpc_network.name
  ip_cidr_range = "10.2.1.0/24"
}

# Firewall
resource "google_compute_firewall" "allow_health_check" {
  name          = "fw-allow-health-check"
  network       = google_compute_network.vpc_network.name
  direction     = "INGRESS"
  target_tags   = ["allow-health-check"]
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

resource "google_compute_firewall" "allow_ssh" {
  name        = "fw-allow-ssh"
  network     = google_compute_network.vpc_network.name
  direction   = "INGRESS"
  target_tags = ["allow-ssh"]
  source_ranges = ["0.0.0.0/22"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_proxy_only_subnet" {
  name          = "fw-allow-proxy-only-subnet"
  network       = google_compute_network.vpc_network.name
  direction     = "INGRESS"
  target_tags   = ["allow-proxy-only-subnet"]
  source_ranges = var.proxy_subnet_ranges

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

resource "google_compute_firewall" "allow_gke_subnet" {
  name          = "fw-allow-gke-subnet"
  network       = google_compute_network.vpc_network.name
  direction     = "INGRESS"
  target_tags   = ["allow-gke-subnet"]
  source_ranges = var.subnet_ranges

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

# LB Configuration
# Premium Tier. If the IP address of the load balancer is in the Premium Tier, the traffic traverses Google's high‑quality global backbone with the intent that packets enter and exit a Google edge peering point as close as possible to the client. If you don't specify a network tier, your load balancer defaults to using the Premium Tier. Note that all internal load balancers are always Premium Tier. Additionally, the global external Application Load Balancer can also only be configured in Premium Tier.

# Backend Service / Backend / NEGs
resource "google_compute_backend_service" "backend_service" {
  name                    = "backend-service"
  load_balancing_scheme   = "INTERNAL_MANAGED"
  locality_lb_policy      = "ROUND_ROBIN"
  protocol                = "HTTP"
  enable_cdn              = false
  connection_draining_timeout_sec = 300
  health_checks           = [google_compute_health_check.gil7_basic_check.id]
  log_config {
    enable      = true
    sample_rate = 1.0
  }

  # backend {
  #   group                   = google_compute_network_endpoint_group.neg_germany.id
  #   balancing_mode          = "RATE"
  #   max_rate_per_endpoint   = local.max_rate_per_endpoint
  # }

  # backend {
  #   group                   = google_compute_network_endpoint_group.neg_belgium.id
  #   balancing_mode          = "RATE"
  #   max_rate_per_endpoint   = local.max_rate_per_endpoint
  # }

}

# resource "google_compute_network_endpoint_group" "neg_germany" {
#   name                  = "neg-de"
#   network_endpoint_type = "GCE_VM_IP_PORT"
#   default_port          = 80
#   zone                  = local.germany_zone_a
#   network               = google_compute_network.vpc_network.name
#   subnetwork            = google_compute_subnetwork.subnetwork_germany.id
# }

# resource "google_compute_network_endpoint_group" "neg_belgium" {
#   name                  = "neg-be"
#   network_endpoint_type = "GCE_VM_IP_PORT"
#   default_port          = 80
#   zone                  = local.belgium_zone_a
#   network               = google_compute_network.vpc_network.name
#   subnetwork            = google_compute_subnetwork.subnetwork_belgium.id
# }

# URL Map
resource "google_compute_url_map" "gil7_map" {
  name            = "gil7-map"
  default_service = google_compute_backend_service.backend_service.id
}

resource "google_compute_target_http_proxy" "gil7_http_proxy" {
  name    = "gil7-http-proxy"
  url_map = google_compute_url_map.gil7_map.id
}

# resource "google_compute_global_forwarding_rule" "fw_rule_germany" {
#   name                  = "l7-ilb-forwarding-rule-de"
#   ip_protocol           = "TCP"
#   load_balancing_scheme = "INTERNAL_MANAGED"
#   port_range            = "80"
#   target                = google_compute_target_http_proxy.gil7_http_proxy.id
#   network               = google_compute_network.vpc_network.id
#   subnetwork            = google_compute_subnetwork.subnetwork_germany.id

#   depends_on            = [google_compute_subnetwork.proxy_subnet_germany]
# }

# resource "google_compute_global_forwarding_rule" "fw_rule_belgium" {
#   name                  = "l7-ilb-forwarding-rule-be"
#   ip_protocol           = "TCP"
#   load_balancing_scheme = "INTERNAL_MANAGED"
#   port_range            = "80"
#   target                = google_compute_target_http_proxy.gil7_http_proxy.id
#   network               = google_compute_network.vpc_network.id
#   subnetwork            = google_compute_subnetwork.subnetwork_belgium.id

#   depends_on            = [google_compute_subnetwork.proxy_subnet_belgium]
# }

# Healthchecks

resource "google_compute_health_check" "gil7_basic_check" {
  name              = "gil7-basic-check"
  check_interval_sec = 5
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 2

  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }
}

###########
# Outputs #
###########

# output "cluster_name" {
#   value = google_container_cluster.autopilot_cluster.name
# }

# output "kubernetes_endpoint" {
#   value = google_container_cluster.autopilot_cluster.endpoint
# }

# output "kubernetes_cluster_ca_certificate" {
#   value = google_container_cluster.autopilot_cluster.master_auth.0.cluster_ca_certificate
# }
