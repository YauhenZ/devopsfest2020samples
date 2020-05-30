## backend

terraform {
    backend "azurerm" {  }
}


## providers 

provider "azurerm" {
    version = "=2.10.0"
    features {}
}


## parameters (common)

variable "environment_name" {
    type = string
}

variable "location" {
  type = string 
  default = "westeurope"
}

variable "infra_vault_rid" {
    type = string
}

variable "hub_environment_name" {
    type = string
    default = ""
}


## default variables

variable "product_name" { 
    default = "backend"
}

locals {
    hub_environment_name = var.hub_environment_name == "" ? var.environment_name : var.hub_environment_name
}


## read dependencies data & configuration

data "azurerm_key_vault_secret" "rg_name" {
    name = "${var.environment_name}-${var.product_name}-output-rg-name"
    key_vault_id  = var.infra_vault_rid
}

data "azurerm_key_vault_secret" "app_insights_instrumentation_key" {
    name = "${local.hub_environment_name}-${var.product_name}hub-output-appinsights-key" 
    key_vault_id  = var.infra_vault_rid
}

data "azurerm_key_vault_secret" "aks_cluster_name" {
    name = "${var.environment_name}-${var.product_name}-output-aks-name" 
    key_vault_id  = var.infra_vault_rid
}

data "azurerm_key_vault_secret" "certificate_crt" {
    name = "${local.hub_environment_name}-${var.product_name}-config-certificate-crt"
    key_vault_id  = var.infra_vault_rid
}

data "azurerm_key_vault_secret" "certificate_key" {
    name = "${local.hub_environment_name}-${var.product_name}-config-certificate-key"
    key_vault_id  = var.infra_vault_rid
}


## create resources

# gather data about aks 
data "azurerm_kubernetes_cluster" "aks_cluster" { 
    name = data.azurerm_key_vault_secret.aks_cluster_name.value 
    resource_group_name = data.azurerm_key_vault_secret.rg_name.value
}

# initialize k8s provider
provider "kubernetes" {
    version = "v1.11.0"
    load_config_file = "false"

    host                   = data.azurerm_kubernetes_cluster.aks_cluster.kube_config.0.host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.aks_cluster.kube_config.0.cluster_ca_certificate)
}


# setup help: initialize provider
provider "helm" {
    version = "v1.0.0"

    kubernetes {
        host                   = data.azurerm_kubernetes_cluster.aks_cluster.kube_config.0.host
        client_certificate     = base64decode(data.azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_certificate)
        client_key             = base64decode(data.azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_key)
        cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.aks_cluster.kube_config.0.cluster_ca_certificate)

        load_config_file = "false"
    }
}

# install traefic (ingress)
data "helm_repository" "stable" {
    name = "stable"
    url  = "https://kubernetes-charts.storage.googleapis.com"
}
resource "helm_release" "traefic" {
    

    name       = "traefik"
    namespace  = "kube-system"
    repository = data.helm_repository.stable.metadata.0.name
    chart      = "traefik"
    version    = "1.73.1"
    
    timeout = 2500

    # Uncomment to expose traefik on private ip 
    # values = [
    #     <<-EOF
    #     service:
    #         annotations:
    #             service.beta.kubernetes.io/azure-load-balancer-internal: true
    #     EOF
    # ]

    set {
        name  = "serviceType"
        value = "LoadBalancer"
    }

    set {
        name  = "debug.enabled"
        value = "false"
    }

    set { 
        name   = "logLevel" 
        value  = "error" 
    }

    set {
        name = "ssl.enabled" 
        value = "true"
    }

    set { 
        name = "rbac.enabled" 
        value = true 
    }
}

# add kube dashboard: create cluster role binding
resource "kubernetes_cluster_role_binding" "kube_dashboard_role_binding" {
    metadata {
        name = "kubernetes-dashboard"
    }
    role_ref {
        api_group = "rbac.authorization.k8s.io"
        kind      = "ClusterRole"
        name      = "cluster-admin"
    }
    subject {
        kind      = "ServiceAccount"
        name      = "kubernetes-dashboard"
        namespace = "kube-system"
    }
}
# add kube dashboard
resource "kubernetes_ingress" "kubernetes_dashboard" {
    metadata {
        name = "kubernetes-dashboard"
        namespace = "kube-system"
    }

    spec {
        rule {
        host = "kube.${var.product_name}-${var.environment_name}.com"
        http {
            path {
            backend {
                service_name = "kubernetes-dashboard"
                service_port = 80
            }
            }
        }
        }
    }
}


# create a secret with app insights instrumentation key
resource "kubernetes_secret" "kube_secret_appinsights" {
    metadata {
        name = "appinsights"
    }

    data = { 
        app_insights_key = data.azurerm_key_vault_secret.app_insights_instrumentation_key.value
    }
}

# create secret with ssl certificate
resource "kubernetes_secret" "default_certificate" {
  metadata {
    name = "defaultcert"
  }

  data = {
    "tls.crt" = data.azurerm_key_vault_secret.certificate_crt.value
    "tls.key" = data.azurerm_key_vault_secret.certificate_key.value
  }

  type = "kubernetes.io/tls"
}

# gather details about ingress service: needed to get ingress private ip
data "kubernetes_service" "traefic" {
    depends_on = [helm_release.traefic]
    metadata {
        name = "traefik"
        namespace = "kube-system"
    }
} 


## write outputs

output "ingress_ip" { 
    value = data.kubernetes_service.traefic.load_balancer_ingress.0.ip
}
resource "azurerm_key_vault_secret" "ingress_ip" {
    name = "${var.environment_name}-${var.product_name}-output-aks-ingressip" 
    value = data.kubernetes_service.traefic.load_balancer_ingress.0.ip
    key_vault_id = var.infra_vault_rid
}