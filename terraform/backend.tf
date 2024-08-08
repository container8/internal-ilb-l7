terraform {
  backend "gcs" {
    bucket = "tf-state-ilb-l7-gke-poc"
    prefix  = ""
  }
}
