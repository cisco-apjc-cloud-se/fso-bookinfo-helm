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
  kube_config = yamldecode(base64decode(data.terraform_remote_state.iks.kube_config))
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
      labels = {
        app = "iwo"
      }
    }
    name = "iwo-collector"
  }
}

### Helm ###

## Add IWO K8S Collector  ##
resource "helm_release" "iwo-collector" {
 namespace   = kubernetes_namespace.iwo-collector.metadata[0].name
 name        = "iwo-collector"

 // repository  = "https://helm.releases.hashicorp.com"
 chart       = "https://iwo-k8s-collector.s3.ap-southeast-2.amazonaws.com/iwo-k8s-collector-v1.0.1.tar.gz"

 set {
   name  = "iwoServerVersion"
   value = "8.2"
 }

 set {
   name  = "collectorImage.tag"
   value = "8.2.1"
 }

 set {
   name  = "targetName"
   value = "iks-cpoc-bookinfo"
 }
}
