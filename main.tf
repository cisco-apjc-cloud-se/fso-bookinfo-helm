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

resource "kubernetes_namespace" "appd" {
  metadata {
    annotations = {
      name = "appdynamics"
    }
    labels = {
      app = "appdynamics"
    }
    name = "appdynamics"
  }
}

resource "kubernetes_namespace" "metrics" {
  metadata {
    annotations = {
      name = "metrics"
    }
    labels = {
      app = "metrics"
    }
    name = "metrics"
  }
}

### Helm ###

// ## Add IWO K8S Collector Release ##
// resource "helm_release" "iwo-collector" {
//  namespace   = kubernetes_namespace.iwo-collector.metadata[0].name
//  name        = "iwo-collector"
//
//  chart       = var.iwo_chart_url
//
//  set {
//    name  = "iwoServerVersion"
//    value = var.iwo_server_version
//  }
//
//  set {
//    name  = "collectorImage.tag"
//    value = var.iwo_collector_image_version
//  }
//
//  set {
//    name  = "targetName"
//    value = var.iwo_cluster_name
//  }
// }

// ## Add Bookinfo Release  ##
// resource "helm_release" "bookinfo" {
//  namespace   = kubernetes_namespace.bookinfo.metadata[0].name
//  name        = "bookinfo"
//
//  chart       = var.bookinfo_chart_url
//
//  set {
//    name  = "appDynamics.account_name"
//    value = var.appd_account_name
//  }
//
//  set {
//    name  = "appDynamics.account_key"
//    value = var.appd_account_key
//  }
//
//  set {
//    name  = "detailsService.replicaCount"
//    value = var.detailsService_replica_count
//  }
//
//  set {
//    name  = "ratingsService.replicaCount"
//    value = var.ratingsService_replica_count
//  }
//
//  set {
//    name  = "reviewsService.replicaCount"
//    value = var.reviewsService_replica_count
//  }
//
//  set {
//    name  = "productPageService.replicaCount"
//    value = var.productPageService_replica_count
//  }
//
// }

## Add Metrics Server Release ##
# - Required for AppD Cluster Agent

resource "helm_release" "metrics-server" {
  name = "metrics-server"
  namespace = "kube-system"
  repository = "https://charts.bitnami.com/bitnami"
  chart = "metrics-server"

  set {
    name = "apiService.create"
    value = true
  }

  set {
    name = "extraArgs.kubelet-insecure-tls"
    value = true
  }

  set {
    name = "extraArgs.kubelet-preferred-address-types"
    value = "InternalIP"
  }

}

// ## Add Appd Cluster Agent Release  ##
// resource "helm_release" "appd-cluster-agent" {
//  namespace   = kubernetes_namespace.appd.metadata[0].name
//  name        = "appd-cluster-agent"
//
//  repository  = "https://ciscodevnet.github.io/appdynamics-charts"
//  chart       = "cluster-agent"
//
//  set {
//    name = "controllerInfo.url"
//    value = format("https://%s.saas.appdynamics.com:443", var.appd_account_name)
//  }
//
//  set {
//    name = "controllerInfo.account"
//    value = var.appd_account_name
//  }
//
//  set {
//    name = "controllerInfo.accessKey"
//    value = var.appd_account_key
//  }
//
//  ## Monitor All Namespaces
//  set {
//    name = "clusterAgent.nsToMonitorRegex"
//    value = ".*"
//  }
//
//  depends_on = [helm_release.metrics-server]
// }
//
// ## Add Appd Machine Agent Release  ##
// resource "helm_release" "appd-machine-agent" {
//  namespace   = kubernetes_namespace.appd.metadata[0].name
//  name        = "appd-machine-agent"
//
//  repository  = "https://ciscodevnet.github.io/appdynamics-charts"
//  chart       = "machine-agent"
//
//  // helm install --namespace=appdynamics \
//  // --set .accessKey=<controller-key> \
//  // --set .host=<*.saas.appdynamics.com> \
//  // --set controller.port=443 --set controller.ssl=true \
//  // --set controller.accountName=<account-name> \
//  // --set controller.globalAccountName=<global-account-name> \
//  // --set analytics.eventEndpoint=https://analytics.api.appdynamics.com \
//  // --set agent.netviz=true serverviz appdynamics-charts/machine-agent
//
//  set {
//    name = "controller.accessKey"
//    value = var.appd_account_key
//  }
//
//  set {
//    name = "controller.host"
//    value = format("%s.saas.appdynamics.com", var.appd_account_name)
//  }
//
//  set {
//    name = "controller.port"
//    value = 443
//  }
//
//  set {
//    name = "controller.ssl"
//    value = true
//  }
//
//  set {
//    name = "controller.accountName"
//    value = var.appd_account_name
//  }
//
//  set {
//    name = "controller.globalAccountName"
//    value = var.appd_account_name
//  }
//
//  set {
//    name = "analytics.eventEndpoint"
//    value = "https://analytics.api.appdynamics.com"
//  }
//
//  set {
//    name = "agent.netviz"
//    value = true
//  }
//
//  set {
//    name = "openshift.scc"
//    value = false
//  }
//
//  depends_on = [helm_release.metrics-server]
// }

// ## Add Prometheus (Kube-state-metrics, node-exporter, alertmanager)  ##
// resource "helm_release" "prometheus" {
//  namespace   = "kube-system"
//  name        = "prometheus"
//
//  repository  = "https://prometheus-community.github.io/helm-charts"
//  chart       = "prometheus"
//
// }





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
