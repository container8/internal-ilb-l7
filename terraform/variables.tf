variable "locations" {
  description = "The location (region or zone) of the GKE cluster"
  type        = list(string)
}

variable "subnet_name" {
  description = "Name of the subnet for the clusters"
  type        = string
  default     = "gke-subnet"
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "gke-vpc"
}

variable "subnet_ranges" {
  type = list(string)  
}

variable "proxy_subnet_ranges" {
  type = list(string)
}

variable "http_port" {
  description = "Port for HTTP traffic"
  type        = number
  default     = 80
}

variable "ssh_public_key_path" {
  type = string
}
