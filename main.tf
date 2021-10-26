terraform {
  backend "remote" {
    hostname = "app.terraform.io"
    organization = "mel-ciscolabs-com"
    workspaces {
      name = "fso-bookinfo-helm"
    }
  }
  required_providers {
    // intersight = {
    //   source = "CiscoDevNet/intersight"
    //   # version = "1.0.12"
    // }
    helm = {
      source = "hashicorp/helm"
      # version = "2.0.2"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

### Remote State - Import Kube Config ###
data "terraform_remote_state" "iks" {
  backend = "remote"

  config = {
    organization = "mel-ciscolabs-com"
    workspaces = {
      name = "fso-bookinfo-iks"
    }
  }
}

### Decode Kube Config ###
locals {
  kube_config = yamldecode(base64decode(data.terraform_remote_state.iks.outputs.kube_config))
}


### Providers ###
provider "kubernetes" {
  # alias = "iks-k8s"

  host                   = local.kube_config.clusters[0].cluster.server
  cluster_ca_certificate = base64decode(local.kube_config.clusters[0].cluster.certificate-authority-data)
  client_certificate     = base64decode(local.kube_config.users[0].user.client-certificate-data)
  client_key             = base64decode(local.kube_config.users[0].user.client-key-data)
}

provider "helm" {
  kubernetes {
    host                   = local.kube_config.clusters[0].cluster.server
    cluster_ca_certificate = base64decode(local.kube_config.clusters[0].cluster.certificate-authority-data)
    client_certificate     = base64decode(local.kube_config.users[0].user.client-certificate-data)
    client_key             = base64decode(local.kube_config.users[0].user.client-key-data)
  }
}

### Kubernetes  ###

### Add Namespaces ###

resource "kubernetes_namespace" "iwo-collector" {
  metadata {
    annotations = {
      name = "iwo-collector"
    }
    labels = {
      app = "iwo"
    }
    name = "iwo-collector"
  }
}

resource "kubernetes_namespace" "bookinfo" {
  metadata {
    annotations = {
      name = "bookinfo"
    }
    labels = {
      app = "bookinfo"
    }
    name = "bookinfo"
  }
}

### Helm ###

## Add IWO K8S Collector  ##
resource "helm_release" "iwo-collector" {
 namespace   = kubernetes_namespace.iwo-collector.metadata[0].name
 name        = "iwo-collector"

 chart       = var.iwo_chart_url

 set {
   name  = "iwoServerVersion"
   value = var.iwo_server_version
 }

 set {
   name  = "collectorImage.tag"
   value = var.iwo_collector_image_version
 }

 set {
   name  = "targetName"
   value = var.iwo_cluster_name
 }
}

data "kubernetes_pod" "iwo" {
  metadata {
    name = helm_release.iwo-collector.name
    namespace = kubernetes_namespace.iwo-collector.metadata[0].name
  }
}

// // kubectl -n iwo-collector port-forward my-iwo-k8s-collector-57fcb8b874-s5ch8 9110
// // curl -s http://localhost:9110/DeviceIdentifiers
// // curl -s http://localhost:9110/SecurityTokens
//
// locals {
//   pod_name = "iwok8scollector-iwo-collector-8f67f989f-ksxp5"
// }
//
// ## Test Provisioner for Geting IWO A
// resource "null_resource" "test" {
//   provisioner "local-exec" {
//     command = "kubectl --server='$(local.kube_config.clusters[0].cluster.server)' --client-certificate='$(base64decode(local.kube_config.clusters[0].cluster.certificate-authority-data))' --client-key='$(base64decode(local.kube_config.users[0].user.client-key-data))' --certificate-authority='$(base64decode(local.kube_config.clusters[0].cluster.certificate-authority-data))' -n $(kubernetes_namespace.iwo-collector.metadata[0].name) port-forward $(var.pod_name) 9110"
//     // interpreter = ["PowerShell", "-Command"]
//   }
//   provisioner "local-exec" {
//     command = "curl -s http://localhost:9110/DeviceIdentifiers"
//   }
//   provisioner "local-exec" {
//     command = "curl -s http://localhost:9110/SecurityTokens"
//   }
// }
