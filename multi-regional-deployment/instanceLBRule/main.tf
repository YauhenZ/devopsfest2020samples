# provider 
provider "azurerm" {
  version = "=1.38.0"
}

# backend
terraform {
  backend "azurerm" {
    key = "platformlbrule.terraform.tfstate"
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


data "azurerm_key_vault_secret" "platform_lb_name" {
    name          =  "${local.hub_environment_name}-platformhub-output-lb-name" 
    key_vault_id  = var.infra_vault_rid
}

data "azurerm_key_vault_secret" "platform_hub_rg" {
    name          =  "${local.hub_environment_name}-platformhub-output-rg-name" 
    key_vault_id  = var.infra_vault_rid
}

data "azurerm_key_vault_secret" "instance_public_ip" {
    name          = "${var.environment_name}-platform-output-ingress-ip"
    key_vault_id  = var.infra_vault_rid
}


resource "azurerm_traffic_manager_endpoint" "example" {
  name                = "${var.environment_name}endpoint"
  resource_group_name = data.azurerm_key_vault_secret.platform_hub_rg.value 
  profile_name        = data.azurerm_key_vault_secret.platform_lb_name.value
  target              = data.azurerm_key_vault_secret.instance_public_ip.value
  type                = "externalEndpoints"
  weight              = 100
}  