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

variable "docker_registry_id" {
    type = string 
    default = ""
}


locals {
    hub_environment_name = var.hub_environment_name == "" ? var.environment_name : var.hub_environment_name
}


## dependencies data

data "azurerm_key_vault_secret" "unique_prefix" {
    name          = "${local.hub_environment_name}-${var.product_name}hub-output-unique-prefix" 
    key_vault_id  = var.infra_vault_rid
}

data "azurerm_key_vault_secret" "aks_windows_profile_username" {
    name          = "${local.hub_environment_name}-${var.product_name}hub-output-akswindows-username" 
    key_vault_id  = var.infra_vault_rid
}

data "azurerm_key_vault_secret" "aks_windows_profile_password" {
    name          = "${local.hub_environment_name}-${var.product_name}hub-output-akswindows-password"
    key_vault_id  = var.infra_vault_rid
}

## resources 

# create rg 
resource "azurerm_resource_group" "instance_rg" {
    name     = "${var.environment_name}_${var.product_name}"
    location = var.location
}

# create virtual network  & subnet 
resource "azurerm_virtual_network" "instance_vnet" {
  name                = "${var.product_name}-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.instance_rg.name
  address_space       = ["10.0.0.0/16"]
}
resource "azurerm_subnet" "instance_aks_subnet" {
  name                 = "aks"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.1.0/24"]
}

# create service principial for AKS 
module "service_principal" {
  source   = "github.com/innovationnorway/terraform-azuread-service-principal"
  name     = "${var.environment_name}${var.product_name}aksspa"
  years    = "2"
}

# configure spa permissions: allow AKS SPA to mannage subnet
resource "azurerm_role_assignment" "aks_spa_to_vnet_assigment" {
    scope              = azurerm_virtual_network.instance_vnet.id
    role_definition_name = "Contributor"
    principal_id       = module.service_principal.object_id
}

# configure permissions: allow AKS SPA to pull images from ACR (container registry)
resource "azurerm_role_assignment" "aks_spa_to_dockerreg_assigment" { 
    count              = var.docker_registry_id == "" ? 0 : 1
    scope              = var.docker_registry_id
    role_definition_name = "AcrPull"
    principal_id       = module.service_principal.object_id
}

# create log analytics workspace 
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
    name = "${var.environment_name}-${var.product_name}-Logs" 
    location = var.location 
    resource_group_name = azurerm_resource_group.instance_rg.name
    sku = "pergb2018"
    retention_in_days = 30 
}

# create AKS 
resource "azurerm_kubernetes_cluster" "aks" {
    name = "${var.environment_name}-${var.product_name}-${data.azurerm_key_vault_secret.unique_prefix.value}"
    location = var.location 
    resource_group_name = azurerm_resource_group.instance_rg.name
    dns_prefix = "${var.environment_name}-${var.product_name}-${data.azurerm_key_vault_secret.unique_prefix.value}"
    
    kubernetes_version = "1.15.10"

    default_node_pool { 
        name            = "main"
        vm_size         = "Standard_F2s_v2" # "Standard_DS1_v2" # "Standard_DS2_v2" F2s v2
        os_disk_size_gb = 100
        max_pods        = 30
        vnet_subnet_id  = azurerm_subnet.instance_aks_subnet.id
        
        type            = "VirtualMachineScaleSets"
        enable_auto_scaling = true  
        min_count = 1 
        max_count = 100
    }

    network_profile { 
        network_plugin = "azure"
        load_balancer_sku = "basic"
    }

    addon_profile {
        oms_agent { 
            enabled = true
            log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id 
        }
    }

    service_principal {
        client_id     = module.service_principal.client_id
        client_secret = module.service_principal.client_secret
    }

    windows_profile { 
        admin_username = data.azurerm_key_vault_secret.aks_windows_profile_username.value
        admin_password = data.azurerm_key_vault_secret.aks_windows_profile_password.value
    }
}

## write outputs to key vault & display in stdout for debugging purposes 

output "rg_name" { 
    value = azurerm_resource_group.instance_rg.name
}
resource "azurerm_key_vault_secret" "rg_name" {
    name = "${var.environment_name}-${var.product_name}-output-rg-name"
    value = azurerm_resource_group.instance_rg.name
    key_vault_id = var.infra_vault_rid
}

output "aks_cluster_name" { 
    value = azurerm_kubernetes_cluster.aks.name
}
resource "azurerm_key_vault_secret" "aks_cluster_name" {
    name = "${var.environment_name}-${var.product_name}-output-aks-name" 
    value = azurerm_kubernetes_cluster.aks.name    
    key_vault_id = var.infra_vault_rid
}