## provider 

provider "azurerm" {
    version = "2.10.0"
    features {}
}

provider "random" {
    version = "2.2.1"
}

provider "azuread" {
    version = "v0.8.0"
}


## backend

terraform {
    backend "azurerm" { }
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


## default variables

variable "product_name" { 
    default = "backend"
}

variable "aks_windows_user" { 
    type = string 
    default = "azureuser"
}


## resources 

# random prefix: some some resources require globally unique name
resource "random_string" "unique_prefix" {
    length  = 4
    special = false
    number  = false 
    upper   = false
}
resource "azurerm_key_vault_secret" "unique_prefix" {
    name = "${var.environment_name}-${var.product_name}hub-output-unique-prefix" 
    value = random_string.unique_prefix.result
    
    key_vault_id = var.infra_vault_rid
}

# create resource group
resource "azurerm_resource_group" "hub_rg" {
    name     = "${var.environment_name}_hub_${var.product_name}"
    location = var.location
}
resource "azurerm_key_vault_secret" "hub_rg" {
    name = "${var.environment_name}-${var.product_name}hub-output-rg-name" 
    value = azurerm_resource_group.hub_rg.name
    
    key_vault_id = var.infra_vault_rid
}

# create shared instance of application insights
resource "azurerm_application_insights" "application_insights" {
    name = "${var.environment_name}${var.product_name}appinsights"
    location = var.location
    resource_group_name = azurerm_resource_group.hub_rg.name 
    application_type = "web"
}
resource "azurerm_key_vault_secret" "appinsights_key" {
    name = "${var.environment_name}-${var.product_name}hub-output-appinsights-key" 
    value = azurerm_application_insights.application_insights.instrumentation_key
    
    key_vault_id = var.infra_vault_rid
}

# generate random AKS windows profile password: without this step AKS will be recreated with each terraform apply  
resource "random_password" "aks_windows_profile_password" {
    length = 20
    special = true
    override_special = "_%@"
}
resource "azurerm_key_vault_secret" "aks_windows_profile_password" {
    name = "${var.environment_name}-${var.product_name}hub-output-akswindows-password" 
    value = random_password.aks_windows_profile_password.result
    
    key_vault_id = var.infra_vault_rid
}
resource "azurerm_key_vault_secret" "aks_windows_profile_username" {
    name = "${var.environment_name}-${var.product_name}hub-output-akswindows-username" 
    value = var.aks_windows_user
    
    key_vault_id = var.infra_vault_rid
}

# create traffic manager profile
resource "azurerm_traffic_manager_profile" "trafic_manager" {
  name                   = "${var.environment_name}${var.product_name}hub${random_string.unique_prefix.result}"
  resource_group_name    = azurerm_resource_group.hub_rg.name
  traffic_routing_method = "Weighted"

  dns_config {
    relative_name = "${var.environment_name}${var.product_name}hub${random_string.unique_prefix.result}"
    ttl           = 20
  }

  monitor_config {
    protocol                     = "http"
    port                         = 80
    path                         = "/"
    interval_in_seconds          = 10
    timeout_in_seconds           = 5
    tolerated_number_of_failures = 1
  }
}
resource "azurerm_key_vault_secret" "lb_name" {
    name = "${var.environment_name}-${var.product_name}hub-output-lb-name" 
    value = azurerm_traffic_manager_profile.trafic_manager.name
    
    key_vault_id = var.infra_vault_rid
}