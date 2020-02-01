# provider 
provider "azurerm" {
  version = "=1.38.0"
}

# backend
terraform {
  backend "azurerm" {
    key = "platform.terraform.tfstate"
  }
}

# parameters (common)
variable "environment_name" {
  type = string
}

# parameters (common)
variable "location" {
  type = string 
  default = "westeurope"
}

# parameters (common) 
variable "infra_vault_rid" {
    type = string
}

variable "hub_environment_name" {
    type = string
}

locals {
  hub_environment_name = var.hub_environment_name == "" ? var.environment_name : var.hub_environment_name
}


data "azurerm_key_vault_secret" "platform_unique_prefix" {
    name          = "${local.hub_environment_name}-platformhub-output-unique-prefix" 
    key_vault_id  = var.infra_vault_rid
}

# create main resource group 
resource "azurerm_resource_group" "platform_rg" {
    name     = "${var.environment_name}_platform"
    location = var.location
}

module "service_principal" {
  source   = "github.com/innovationnorway/terraform-azuread-service-principal"
  name     = "aksspa${var.environment_name}"
  end_date = "2Y"
}

resource "azurerm_kubernetes_cluster" "platform_aks" {
    name = "AKS-${var.environment_name}-${data.azurerm_key_vault_secret.platform_unique_prefix.value}"
    location = var.location 
    resource_group_name = azurerm_resource_group.platform_rg.name
    dns_prefix = "AKS-${var.environment_name}-${data.azurerm_key_vault_secret.platform_unique_prefix.value}"

    default_node_pool { 
        name            = "main"
        vm_size         = "Standard_DS2_v2"
        # os_type         = "Linux"
        os_disk_size_gb = 100
        max_pods        = 30
        
        # type            = "VirtualMachineScaleSets"
        # enable_auto_scaling = true  
        # node_count           = 3
        # min_count = 3 
        # max_count = 10

        type            = "AvailabilitySet"
        node_count           = 2
    }

    network_profile { 
        network_plugin = "azure"
        load_balancer_sku = "basic"
    }

    service_principal {
        client_id     = module.service_principal.client_id
        client_secret = module.service_principal.client_secret
    }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.platform_aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.platform_aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.platform_aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.platform_aks.kube_config.0.cluster_ca_certificate)
}

# setup helm: create service account
resource "kubernetes_service_account" "helm_service_account" { 
    metadata {
        name                  = "tiller"
        namespace             = "kube-system" 
    } 
}

# setup helm: create cluster role binding 
resource "kubernetes_cluster_role_binding" "helm_service_account_role_binding" {
    metadata {
        name = "tiller"
    }
    role_ref {
        api_group = "rbac.authorization.k8s.io"
        kind      = "ClusterRole"
        name      = "cluster-admin"
    }
    subject {
        kind      = "ServiceAccount"
        name      = "tiller"
        namespace = "kube-system"
    }
}

# setup help: initialize provider
provider "helm" {
    kubernetes {
        host                   = azurerm_kubernetes_cluster.platform_aks.kube_config.0.host
        client_certificate     = base64decode(azurerm_kubernetes_cluster.platform_aks.kube_config.0.client_certificate)
        client_key             = base64decode(azurerm_kubernetes_cluster.platform_aks.kube_config.0.client_key)
        cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.platform_aks.kube_config.0.cluster_ca_certificate)
    }

    install_tiller = true 
    service_account = "tiller"
}

# create cluster role binding for kubernetes-dashboard
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

# install traefic
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
    
    timeout = 1000

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


# demo app deployment 

resource "kubernetes_deployment" "example" {
  metadata {
    name = "terraform-example"
    labels = {
      test = "MyExampleApp"
    }
  }

  spec {
    replicas = 3

    selector {
      match_labels = {
        test = "MyExampleApp"
      }
    }

    template {
      metadata {
        labels = {
          test = "MyExampleApp"
        }
      }

      spec {
        container {
          image = "nginx:1.7.8"
          name  = "example"

          resources {
            limits {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests {
              cpu    = "250m"
              memory = "50Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "example" {
  metadata {
    name = "terraform-example"
  }
  spec {
    selector = {
      test = "MyExampleApp"
    }
    session_affinity = "ClientIP"
    port {
      port        = 8080
      target_port = 80
    }

    type = "LoadBalancer"
  }
}

resource "kubernetes_ingress" "example_ingress" {
  metadata {
    name = "example-ingress"
  }

  spec {
    backend {
      service_name = "terraform-example"
      service_port = 8080
    }

    rule {
      http {
        path {
          backend {
            service_name = "terraform-example"
            service_port = 8080
          }

          path = "/*"
        }
      }
    }
  }
}


# writting outputs

data "kubernetes_service" "traefic" {
  depends_on = [helm_release.traefic]
  metadata {
    name = "traefik"
    namespace = "kube-system"
  }
} 

resource "azurerm_key_vault_secret" "instance_public_ip" {
    name = "${var.environment_name}-platform-output-ingress-ip" 
    value = data.kubernetes_service.traefic.load_balancer_ingress.0.ip
    
    key_vault_id = var.infra_vault_rid
}

# This output is temporary and should not be referenced anywhere
output "ingress_ip" { 
    value = data.kubernetes_service.traefic.load_balancer_ingress.0.ip
}

