##########
# Locals #
##########

locals {
  germany = "us-central1"
  germany_zone_a = "us-central1-a"
  belgium = "us-east1"
  belgium_zone_a = "us-east1-b"
  max_rate_per_endpoint = 100
  belgium_zones = [
    "us-east1-b",
    "us-east1-c",
    "us-east1-d"
  ]
  germany_zones = [
    "us-central1-a",
    "us-central1-b",
    "us-central1-c"
  ]
  germany_neg_name = "nginx-neg-germany"
  belgium_neg_name = "nginx-neg-belgium"

  # Networks
  subnet_belgium_cidr = "10.1.0.0/16"
  subnet_vm_cidr      = "10.2.0.0/24"
  subnet_germany_cidr = "10.100.0.0/16"

  subnet_proxy_global_belgium_cidr = "10.2.1.0/24"
  subnet_proxy_only_belgium_cidr   = "10.2.2.0/24"
  subnet_proxy_only_germany_cidr   = "10.2.3.0/24"

  internal_http_lb_address_germany = "10.128.0.100"
  internal_https_lb_address_germany = "10.128.0.101"
  internal_regional_https_lb_address_germany = "10.128.0.102"
  internal_ip_germany_tcp_germany = "10.128.0.103"

  gateway_ip_germany = "10.100.0.10"
  gateway_ip_belgium = "10.1.0.10"
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

  network    = data.google_compute_network.default.self_link
  subnetwork = google_compute_subnetwork.subnetwork_belgium.self_link

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

  network    = data.google_compute_network.default.self_link
  subnetwork = google_compute_subnetwork.subnetwork_germany.self_link

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

data "google_compute_network" "default" {
  name = "default"
}

data "google_compute_subnetwork" "default" {
  name   = "default"
  region = local.germany
}

resource "google_compute_subnetwork" "subnetwork_germany" {
  name          = "subnet-germany"
  ip_cidr_range = local.subnet_germany_cidr
  network       = data.google_compute_network.default.self_link
  region        = local.germany
}

resource "google_compute_subnetwork" "subnetwork_belgium" {
  name          = "subnet-belgium"
  ip_cidr_range = local.subnet_belgium_cidr
  network       = data.google_compute_network.default.self_link
  region        = local.belgium
}

resource "google_compute_subnetwork" "subnetwork_vm_germany" {
  name          = "subnetwork-vm-de"
  network       = data.google_compute_network.default.self_link
  ip_cidr_range = local.subnet_vm_cidr
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
    network    = data.google_compute_network.default.self_link
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

  tags = ["allow-ssh"]
}

#################
# Load Balancer #
#################

# Already exist? (check)
# This proxy-only subnet is used by all Envoy-based regional load balancers in the same region of the VPC network. There can only be one active proxy-only subnet for a given purpose, per region, per network.
# At any point, only one subnet with purpose GLOBAL_MANAGED_PROXY can be active in each region of a VPC network.
# A proxy-only subnet must provide 64 or more IP addresses (min /26, recommended /23)
# Should be centrally managed for the network

resource "google_compute_subnetwork" "proxy_only_subnet_germany" {
  name          = "proxy-only-subnet-de"
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
  region        = local.germany
  network       = data.google_compute_network.default.self_link
  ip_cidr_range = local.subnet_proxy_only_germany_cidr
}

resource "google_compute_subnetwork" "proxy_only_subnet_belgium" {
  name          = "proxy-only-subnet-be"
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
  region        = local.belgium
  network       = data.google_compute_network.default.self_link
  ip_cidr_range = local.subnet_proxy_only_belgium_cidr
}

resource "google_compute_subnetwork" "proxy_subnet_belgium" {
  name          = "proxy-subnet-be"
  purpose       = "GLOBAL_MANAGED_PROXY"
  role          = "ACTIVE"
  region        = local.belgium
  network       = data.google_compute_network.default.self_link
  ip_cidr_range = local.subnet_proxy_global_belgium_cidr
}

# Firewall
resource "google_compute_firewall" "allow_health_check" {
  name          = "fw-allow-health-check"
  network       = data.google_compute_network.default.self_link
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
  network     = data.google_compute_network.default.self_link
  direction   = "INGRESS"
  target_tags = ["allow-ssh"]
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_proxy_only_subnet" {
  name          = "fw-allow-proxy-only-subnet"
  network       = data.google_compute_network.default.self_link
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
  network       = data.google_compute_network.default.self_link
  direction     = "INGRESS"
  target_tags   = ["allow-gke-subnet"]
  source_ranges = var.subnet_ranges

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

resource "google_compute_firewall" "allow_http_traffic" {
  name          = "allow-http-traffic"
  network       = data.google_compute_network.default.self_link

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

# LB Configuration
# Premium Tier. If the IP address of the load balancer is in the Premium Tier, the traffic traverses Google's high‑quality global backbone with the intent that packets enter and exit a Google edge peering point as close as possible to the client. If you don't specify a network tier, your load balancer defaults to using the Premium Tier. Note that all internal load balancers are always Premium Tier. Additionally, the global external Application Load Balancer can also only be configured in Premium Tier.

# Backend Service / Backend / NEGs
# Using dynamic NEGs with autoneg-controller
resource "google_compute_backend_service" "backend_service" {
  name                    = "backend-service"
  load_balancing_scheme   = "INTERNAL_MANAGED"
  locality_lb_policy      = "ROUND_ROBIN"
  session_affinity        = "NONE"
  protocol                = "HTTP"
  enable_cdn              = false
  connection_draining_timeout_sec = 300
  health_checks           = [google_compute_health_check.gil7_basic_check.id]
  log_config {
    enable      = true
    sample_rate = 1.0
  }

  # Ignore changes to the "tags" attribute
  lifecycle {
    ignore_changes = [
      backend
    ]
  }
}

# Using predefined NEGs
# These are not cleaned up automatically on GKE destroy
# data "google_compute_network_endpoint_group" "negs_germany" {
#   for_each = toset(local.germany_zones)

#   name = local.germany_neg_name
#   zone = each.value
# }

# data "google_compute_network_endpoint_group" "negs_belgium" {
#   for_each = toset(local.belgium_zones)

#   name = local.belgium_neg_name
#   zone = each.value
# }

resource "google_compute_backend_service" "backend_service_germany" {
  name                    = "backend-service-germany"
  load_balancing_scheme   = "INTERNAL_MANAGED"
  locality_lb_policy      = "ROUND_ROBIN"
  session_affinity        = "HTTP_COOKIE"
  protocol                = "HTTP"
  enable_cdn              = false
  connection_draining_timeout_sec = 300
  health_checks           = [google_compute_health_check.gil7_basic_check.id]
  log_config {
    enable      = true
    sample_rate = 1.0
  }

  # dynamic "backend" {
  #   for_each = data.google_compute_network_endpoint_group.negs_germany

  #   content {
  #     group = backend.value.id
  #     balancing_mode = "RATE"
  #     max_rate = 60
  #   }
  # }
}

resource "google_compute_backend_service" "backend_service_belgium" {
  name                    = "backend-service-belgium"
  load_balancing_scheme   = "INTERNAL_MANAGED"
  locality_lb_policy      = "ROUND_ROBIN"
  session_affinity        = "HTTP_COOKIE"
  protocol                = "HTTP"
  enable_cdn              = false
  connection_draining_timeout_sec = 300
  health_checks           = [google_compute_health_check.gil7_basic_check.id]
  log_config {
    enable      = true
    sample_rate = 1.0
  }

  # dynamic "backend" {
  #   for_each = data.google_compute_network_endpoint_group.negs_belgium

  #   content {
  #     group = backend.value.id
  #     balancing_mode = "RATE"
  #     max_rate = 60
  #   }
  # }
}

resource "google_compute_backend_service" "backend_service_europe_tcp" {
  name                    = "backend-service-europe-tcp"
  load_balancing_scheme   = "INTERNAL_MANAGED"
  locality_lb_policy      = "ROUND_ROBIN"
  session_affinity        = "NONE"
  #session_affinity        = "CLIENT_IP" # HTTP Cookie will not work here
  protocol                = "TCP"
  enable_cdn              = false
  connection_draining_timeout_sec = 300
  health_checks           = [google_compute_health_check.gil4_basic_check.id]
  log_config {
    enable      = true
    sample_rate = 1.0
  }

  backend {
    group = google_compute_network_endpoint_group.neg_germany.id
    balancing_mode = "CONNECTION"
    max_connections_per_endpoint = 100
  }
  
  backend {
    group = google_compute_network_endpoint_group.neg_belgium.id
    balancing_mode = "CONNECTION"
    max_connections_per_endpoint = 100
  }

  # lifecycle {
  #   ignore_changes = [
  #     backend
  #   ]
  # }
}

# NEGS for the Gateway IP addresses
resource "google_compute_network_endpoint_group" "neg_germany" {
  name                  = "germany-neg"
  zone                  = local.germany_zones[0]
  network               = data.google_compute_network.default.self_link
  default_port          = "80"
  network_endpoint_type = "NON_GCP_PRIVATE_IP_PORT"
}

resource "google_compute_network_endpoint" "germany_gateway_endpoint" {
  network_endpoint_group = google_compute_network_endpoint_group.neg_germany.name
  zone                   = local.germany_zones[0]
  port                   = google_compute_network_endpoint_group.neg_germany.default_port
  ip_address             = local.gateway_ip_germany
}

resource "google_compute_network_endpoint_group" "neg_belgium" {
  name                  = "belgium-neg"
  zone                  = local.belgium_zones[0]
  network               = data.google_compute_network.default.self_link
  default_port          = "80"
  network_endpoint_type = "NON_GCP_PRIVATE_IP_PORT"
}

resource "google_compute_network_endpoint" "belgium_gateway_endpoint" {
  network_endpoint_group = google_compute_network_endpoint_group.neg_belgium.name
  zone                   = local.belgium_zones[0]
  port                   = google_compute_network_endpoint_group.neg_belgium.default_port
  ip_address             = local.gateway_ip_belgium
}

resource "google_compute_backend_service" "backend_service_europe" {
  name                    = "backend-service-europe"
  load_balancing_scheme   = "INTERNAL_MANAGED"
  locality_lb_policy      = "ROUND_ROBIN"
  session_affinity        = "HTTP_COOKIE"
  protocol                = "HTTP"
  enable_cdn              = false
  connection_draining_timeout_sec = 300
  health_checks           = [google_compute_health_check.gil7_basic_check.id]
  log_config {
    enable      = true
    sample_rate = 1.0
  }

  # dynamic "backend" {
  #   for_each = merge(
  #     data.google_compute_network_endpoint_group.negs_belgium,
  #     data.google_compute_network_endpoint_group.negs_germany
  #   )

  #   content {
  #     group = backend.value.id
  #     balancing_mode = "RATE"
  #     max_rate = 60
  #   }
  # }
}

resource "google_compute_region_backend_service" "region_backend_service_germany" {
  name                    = "backend-service-germany"
  region = local.germany
  load_balancing_scheme   = "INTERNAL_MANAGED"
  locality_lb_policy      = "ROUND_ROBIN"
  session_affinity        = "HTTP_COOKIE"
  protocol                = "HTTP"
  enable_cdn              = false
  connection_draining_timeout_sec = 300
  health_checks           = [google_compute_health_check.gil7_basic_check.id]
  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_region_backend_service" "region_backend_service_belgium" {
  name                    = "backend-service-belgium"
  region = local.belgium
  load_balancing_scheme   = "INTERNAL_MANAGED"
  locality_lb_policy      = "ROUND_ROBIN"
  session_affinity        = "HTTP_COOKIE"
  protocol                = "HTTP"
  enable_cdn              = false
  connection_draining_timeout_sec = 300
  health_checks           = [google_compute_health_check.gil7_basic_check.id]
  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# Healthchecks
resource "google_compute_health_check" "gil7_basic_check" {
  name                = "gil7-basic-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }
}

resource "google_compute_health_check" "gil4_basic_check" {
  name                = "gil4-basic-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  tcp_health_check {
    port = "80"
  }
}

# URL Map
resource "google_compute_target_http_proxy" "gil7_http_proxy" {
  name    = "gil7-http-proxy"
  url_map = google_compute_url_map.http_urlmap.id
}

# # 'projects/ilb-l7-gke-poc/global/sslCertificates/global-certificate'. Compute SSL certificates are not supported with global INTERNAL_MANAGED load balancer., invalid
# data "google_compute_ssl_certificate" "global-ssl-certificate" {
#   name    = "global-certificate"
# }

# # Error: Error creating TargetHttpsProxy: googleapi: Error 400: Invalid value for field 'resource.sslCertificates[0]': 'projects/ilb-l7-gke-poc/global/sslCertificates/regional-certificate'. Compute SSL certificates are not supported with global INTERNAL_MANAGED load balancer., invalid
# data "google_compute_region_ssl_certificate" "regional-ssl-certificate" {
#   name    = "regional-certificate"

#   region = "us-central1"
# }

# This works
resource "google_certificate_manager_certificate" "cert-manager-certificate" {
  name        = "cert-manager-certificate"
  description = "Global cert"
  scope       = "ALL_REGIONS"
  self_managed {
    pem_certificate = file("../ca-certs/server-cert.pem")
    pem_private_key = file("../ca-certs/server-key.pem")
  }
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/privateca_certificate
# resource "google_privateca_ca_pool" "default" {
#   location = "us-central1"
#   name = "default"
#   tier = "ENTERPRISE"
# }

# resource "google_privateca_certificate_authority" "default" {
#   location = "us-central1"
#   pool = google_privateca_ca_pool.default.name
#   certificate_authority_id = "my-authority"
#   config {
#     subject_config {
#       subject {
#         organization = "HashiCorp"
#         common_name = "my-certificate-authority"
#       }
#       subject_alt_name {
#         dns_names = ["hashicorp.com"]
#       }
#     }
#     x509_config {
#       ca_options {
#         is_ca = true
#       }
#       key_usage {
#         base_key_usage {
#           cert_sign = true
#           crl_sign = true
#         }
#         extended_key_usage {
#           server_auth = true
#         }
#       }
#     }
#   }
#   key_spec {
#     algorithm = "RSA_PKCS1_4096_SHA256"
#   }

#   // Disable CA deletion related safe checks for easier cleanup.
#   deletion_protection                    = false
#   skip_grace_period                      = true
#   ignore_active_certificates_on_deletion = true
# }

# resource "tls_private_key" "cert_key" {
#   algorithm = "RSA"
# }

# resource "google_privateca_certificate" "default" {
#   location = "us-central1"
#   pool = google_privateca_ca_pool.default.name
#   certificate_authority = google_privateca_certificate_authority.default.certificate_authority_id
#   lifetime = "86000s"
#   name = "cert-1"
#   config {
#     subject_config  {
#       subject {
#         common_name = "san1.example.com"
#         country_code = "us"
#         organization = "google"
#         organizational_unit = "enterprise"
#         locality = "mountain view"
#         province = "california"
#         street_address = "1600 amphitheatre parkway"
#       } 
#       subject_alt_name {
#         email_addresses = ["email@example.com"]
#         ip_addresses = ["127.0.0.1"]
#         uris = ["http://www.ietf.org/rfc/rfc3986.txt"]
#       }
#     }
#     x509_config {
#       ca_options {
#         is_ca = true
#       }
#       key_usage {
#         base_key_usage {
#           cert_sign = true
#           crl_sign = true
#         }
#         extended_key_usage {
#           server_auth = false
#         }
#       }
#       name_constraints {
#         critical                  = true
#         permitted_dns_names       = ["*.example.com"]
#         excluded_dns_names        = ["*.deny.example.com"]
#         permitted_ip_ranges       = ["10.0.0.0/8"]
#         excluded_ip_ranges        = ["10.1.1.0/24"]
#         permitted_email_addresses = [".example.com"]
#         excluded_email_addresses  = [".deny.example.com"]
#         permitted_uris            = [".example.com"]
#         excluded_uris             = [".deny.example.com"]
#       }
#     }
#     public_key {
#       format = "PEM"
#       key = base64encode(tls_private_key.cert_key.public_key_pem)
#     }
#   }
# }


# Does global certificate works with INTERNAL_MANAGED global forwarding rule?
resource "google_compute_target_https_proxy" "gil7_https_proxy" {
  name    = "gil7-https-proxy"
  url_map = google_compute_url_map.http_urlmap.id

  certificate_manager_certificates = [google_certificate_manager_certificate.cert-manager-certificate.id] # Works
  #ssl_certificates = [google_privateca_certificate.default.id] # Error
  #ssl_certificates = [data.google_compute_ssl_certificate.global-ssl-certificate.self_link] # Error
  #ssl_certificates = [data.google_compute_region_ssl_certificate.regional-ssl-certificate.self_link] # Error
  #certificate_manager_certificates = [data.google_compute_ssl_certificate.global-ssl-certificate.self_link] # Error
  #certificate_manager_certificates = [data.google_compute_region_ssl_certificate.regional-ssl-certificate.self_link] # Error
  #ssl_policy       = google_compute_ssl_policy.ssl-policy.id
}

# resource "google_compute_region_target_https_proxy" "regional_gil7_https_proxy" {
#   name    = "regional-gil7-https-proxy"
#   region  = local.germany
#   url_map = google_compute_region_url_map.http_urlmap.id

#   ssl_certificates = [data.google_compute_ssl_certificate.global-ssl-certificate.self_link]
#   #ssl_policy       = google_compute_ssl_policy.ssl-policy.id
# }

resource "google_compute_target_tcp_proxy" "gil4_tcp_proxy" {
  name            = "gil4-tcp-proxy"
  backend_service = google_compute_backend_service.backend_service_europe_tcp.self_link
}

resource "google_compute_address" "internal_ip_germany_http" {
  name         = "ilb-internal-ip-http"
  subnetwork   = data.google_compute_subnetwork.default.id
  address_type = "INTERNAL"
  address      = local.internal_http_lb_address_germany # 10.128.0.0/20
  region       = local.germany
}

resource "google_compute_address" "internal_ip_germany_https" {
  name         = "ilb-internal-ip-https"
  subnetwork   = data.google_compute_subnetwork.default.id
  address_type = "INTERNAL"
  address      = local.internal_https_lb_address_germany # 10.128.0.0/20
  region       = local.germany
}

resource "google_compute_address" "regional_internal_ip_germany_https" {
  name         = "regional-ilb-internal-ip-https"
  subnetwork   = data.google_compute_subnetwork.default.id
  address_type = "INTERNAL"
  address      = local.internal_regional_https_lb_address_germany # 10.128.0.0/20
  region       = local.germany
}

resource "google_compute_address" "internal_ip_germany_tcp" {
  name         = "ilb-internal-ip-tcp"
  subnetwork   = data.google_compute_subnetwork.default.id
  address_type = "INTERNAL"
  address      = local.internal_ip_germany_tcp_germany # 10.128.0.0/20
  region       = local.germany
}

resource "google_compute_global_forwarding_rule" "fw_rule_germany_https" {
  name                  = "l7-ilb-forwarding-rule-https"
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.gil7_https_proxy.id
  ip_address            = google_compute_address.internal_ip_germany_https.address
}

# resource "google_compute_forwarding_rule" "regional_fw_rule_germany_https" {
#   name                  = "l7-ilb-forwarding-rule-https"
#   ip_protocol           = "TCP"
#   load_balancing_scheme = "INTERNAL_MANAGED"
#   region                = local.germany
#   port_range            = "443"
#   target                = google_compute_region_target_https_proxy.regional_gil7_https_proxy.id
#   ip_address            = google_compute_address.regional_internal_ip_germany_https.address
# }

resource "google_compute_global_forwarding_rule" "fw_rule_germany_http" {
  name                  = "l7-ilb-forwarding-rule-http"
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.gil7_http_proxy.id
  ip_address            = google_compute_address.internal_ip_germany_http.address
}

resource "google_compute_global_forwarding_rule" "fw_rule_germany_tcp" {
  name                  = "l7-ilb-forwarding-rule-tcp"
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_tcp_proxy.gil4_tcp_proxy.id
  ip_address            = google_compute_address.internal_ip_germany_tcp.address
}

# Questions - what happens if?
# What if load balancer fails - failover to regional load balancers is required?
# https://medium.com/google-cloud/gcp-cross-region-internal-application-load-balancer-why-and-how-f3a33226d690
# the header is not present?
# One of the services does not have active NEGs? How to do failover?
resource "google_compute_url_map" "http_urlmap" {
  name    = "http-urlmap"
  default_service = google_compute_backend_service.backend_service_belgium.self_link

  host_rule {
    hosts        = ["dev.example.com"]  # Assuming a single host for simplicity
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.backend_service_europe.self_link
    
    # path_rule {
    #   paths   = ["/*"]
    #   route_action {
    #     weighted_backend_services {
    #       backend_service = google_compute_backend_service.backend_service_germany.self_link
    #       weight = 50
    #     }
    #     weighted_backend_services {
    #       backend_service = google_compute_backend_service.backend_service_belgium.self_link
    #       weight = 50
    #     }
    #   }
    # }
    route_rules {
      priority = 100
      #service = google_compute_backend_service.backend_service_germany.self_link
      #Failover by changing service backend to one containing endpoints from both regions
      #Failover takes around 5-10 seconds
      service = google_compute_backend_service.backend_service_europe.self_link
      match_rules {
        prefix_match = "/"
        ignore_case = true
        header_matches {
          header_name = "X-Country"
          exact_match = "Germany"
        }
      }
    }
    route_rules {
      priority = 200
      service = google_compute_backend_service.backend_service_belgium.self_link
      match_rules {
        ignore_case = true
        prefix_match = "/"
        header_matches {
          header_name = "X-Country"
          exact_match = "Belgium"
        }
      }
    }
  }

  # path_matcher {
  #   name            = "header_based_routing"
  #   default_service = google_compute_backend_service.backend_service_germany.self_link

  #   # Path rule to match all paths
  #   route_rules {
  #     priority = 1
  #     match_rules {
  #       header_matches {
  #         header_name = "X-Country"
  #         exact_match = "Germany"
  #         invert_match = true
  #       }
  #       ignore_case = true
  #     }
  #   }
  #   path_rule {
  #     paths = ["/*"]
  #     service = google_compute_backend_service.backend_service_germany.self_link
  #   }
  # }
}

resource "google_compute_region_url_map" "http_urlmap" {
  name    = "http-urlmap"
  region = local.germany
  default_service = google_compute_region_backend_service.region_backend_service_germany.self_link

  host_rule {
    hosts        = ["dev.example.com"]  # Assuming a single host for simplicity
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_region_backend_service.region_backend_service_germany.self_link
    
    route_rules {
      priority = 100
      #service = google_compute_backend_service.backend_service_germany.self_link
      #Failover by changing service backend to one containing endpoints from both regions
      #Failover takes around 5-10 seconds
      service = google_compute_region_backend_service.region_backend_service_germany.self_link
      match_rules {
        prefix_match = "/"
        ignore_case = true
        header_matches {
          header_name = "X-Country"
          exact_match = "Germany"
        }
      }
    }
    # Not allowed to have another backend service in belgium
    # route_rules {
    #   priority = 200
    #   service = google_compute_region_backend_service.region_backend_service_belgium.self_link
    #   match_rules {
    #     ignore_case = true
    #     prefix_match = "/"
    #     header_matches {
    #       header_name = "X-Country"
    #       exact_match = "Belgium"
    #     }
    #   }
    # }
  }
}


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
