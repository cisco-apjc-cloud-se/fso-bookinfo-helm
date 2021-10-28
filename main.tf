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

// resource "kubernetes_namespace" "metrics" {
//   metadata {
//     annotations = {
//       name = "metrics"
//     }
//     labels = {
//       app = "metrics"
//     }
//     name = "metrics"
//   }
// }

### Helm ###

## Add IWO K8S Collector Release ##
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

## Add Bookinfo Release  ##
resource "helm_release" "bookinfo" {
 namespace   = kubernetes_namespace.bookinfo.metadata[0].name
 name        = "bookinfo"

 chart       = var.bookinfo_chart_url

 set {
   name  = "appDynamics.account_name"
   value = var.appd_account_name
 }

 set {
   name  = "appDynamics.account_key"
   value = var.appd_account_key
 }

 set {
   name  = "detailsService.replicaCount"
   value = var.detailsService_replica_count
 }

 set {
   name  = "ratingsService.replicaCount"
   value = var.ratingsService_replica_count
 }

 set {
   name  = "reviewsService.replicaCount"
   value = var.reviewsService_replica_count
 }

 set {
   name  = "productPageService.replicaCount"
   value = var.productPageService_replica_count
 }

}

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

## Add Appd Cluster Agent Release  ##
resource "helm_release" "appd-cluster-agent" {
 namespace   = kubernetes_namespace.appd.metadata[0].name
 name        = "appd-cluster-agent"

 repository  = "https://ciscodevnet.github.io/appdynamics-charts"
 chart       = "cluster-agent"

 set {
   name = "controllerInfo.url"
   value = format("https://%s.saas.appdynamics.com:443", var.appd_account_name)
 }

 set {
   name = "controllerInfo.account"
   value = var.appd_account_name
 }

 set {
   name = "controllerInfo.accessKey"
   value = var.appd_account_key
 }

 // set {
 //   name = "install.metrics-server"
 //   value = true
 // }

 set {
   name = "clusterAgent.nsToMonitor"
   value = "[bookinfo]"
 }

 // values = [<<EOF
 // imageInfo:
 //   agentImage: docker.io/appdynamics/cluster-agent
 //   agentTag: 20.7.0
 //   operatorImage: docker.io/appdynamics/cluster-agent-operator
 //   operatorTag: latest
 //   imagePullPolicy: Always
 //
 // controllerInfo:
 //   url: <controller-url>
 //   account: <controller-account>
 //   username: <controller-username>
 //   password: <controller-password>
 //   accessKey: <controller-accesskey>
 //
 // agentServiceAccount: appdynamics-cluster-agent
 // operatorServiceAccount: appdynamics-operator
 // EOF
 // ]

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
