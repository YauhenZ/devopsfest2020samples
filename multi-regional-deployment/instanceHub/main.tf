# provider 
provider "azurerm" {
  version = "=1.38.0"
}

# backend
terraform {
  backend "azurerm" {
    key = "instancehub.terraform.tfstate"
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

# parameters (common): key vault 
variable "infra_vault_rid" {
    type = string
}


resource "random_string" "platform_unique_prefix" {
    length  = 4
    special = false
    number  = false 
    upper   = false
}

resource "azurerm_key_vault_secret" "platform_unique_prefix" {
    name = "${var.environment_name}-platformhub-output-unique-prefix" 
    value = random_string.platform_unique_prefix.result
    
    key_vault_id = var.infra_vault_rid
}


resource "azurerm_resource_group" "platform_hub_rg" {
    name     = "${var.environment_name}_hub_platform"
    location = var.location
}

resource "azurerm_traffic_manager_profile" "platform_trafic_manager" {
  name                   = "${var.environment_name}platformhub${random_string.platform_unique_prefix.result}"
  resource_group_name    = azurerm_resource_group.platform_hub_rg.name
  traffic_routing_method = "Weighted"

  dns_config {
    relative_name = "${var.environment_name}platformhub${random_string.platform_unique_prefix.result}"
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

resource "azurerm_key_vault_secret" "platform_hub_rg" {
    name = "${var.environment_name}-platformhub-output-rg-name" 
    value = azurerm_resource_group.platform_hub_rg.name
    
    key_vault_id = var.infra_vault_rid
}

resource "azurerm_key_vault_secret" "platform_lb_name" {
    name = "${var.environment_name}-platformhub-output-lb-name" 
    value = azurerm_traffic_manager_profile.platform_trafic_manager.name
    
    key_vault_id = var.infra_vault_rid
}