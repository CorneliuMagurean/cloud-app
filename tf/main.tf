# --- Required providers ---
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

# --- Google Cloud Provider Configuration ---
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# --- Google Compute Address (Global for HTTP(S) Load Balancer) ---
resource "google_compute_address" "cloud_app_load_balancer_ip" {
  name    = "cloud-app-external-ip"
  project = var.project_id
  address_type = "EXTERNAL"
  region       = var.region
  lifecycle {
    prevent_destroy = false
  }
}

# --- GKE Cluster Resources ---
resource "google_container_cluster" "primary" {
  name     = "cloud-application"
  location = var.zone

  network    = "default"
  subnetwork = "default"

  remove_default_node_pool = true
  initial_node_count       = 1
  
  deletion_protection = false

  addons_config {
    http_load_balancing {
      disabled = false
    }
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "primary-node-pool"
  cluster    = google_container_cluster.primary.name
  location   = var.zone
  node_count = 1

  node_config {
    machine_type = "e2-medium"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
    ]
    preemptible = true
  }

  autoscaling {
    max_node_count = 8
    min_node_count = 1
  }

  # Required to ensure the node pool is deleted before the cluster.
  lifecycle {
    create_before_destroy = true
  }
}

# --- Kubernetes Provider Configuration ---
data "google_container_cluster" "gke_cluster_data" {
  name     = google_container_cluster.primary.name
  location = var.zone
}

data "google_client_config" "current" {}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.gke_cluster_data.endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.gke_cluster_data.master_auth[0].cluster_ca_certificate)
}

# --- Helm Provider Configuration ---
provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.gke_cluster_data.endpoint}"
    token                  = data.google_client_config.current.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.gke_cluster_data.master_auth[0].cluster_ca_certificate)
  }
}

# --- Install NGINX Ingress Controller using Helm ---
resource "helm_release" "nginx_ingress_controller" {
  name             = "nginx-ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  set {
    name  = "controller.service.loadBalancerIP"
    value = google_compute_address.cloud_app_load_balancer_ip.address
  }
}

# Output the external IP address of the load balancer
output "load_balancer_ip" {
  description = "The external IP address of the Google Cloud Load Balancer."
  value       = google_compute_address.cloud_app_load_balancer_ip.address
}
