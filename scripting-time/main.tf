# provider 
provider "azurerm" {
  version = "=1.38.0"
}

# backend
terraform {
  backend "azurerm" {
    key = "wrapperdemo.terraform.tfstate"
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


# script itself

resource "random_string" "resources_unique_prefix" {
    length  = 4
    special = false
    number  = false 
    upper   = false
}

resource "azurerm_key_vault_secret" "resources_unique_prefix" {
    name = "${var.environment_name}-wrapperdemo-output-unique-prefix" 
    value = random_string.resources_unique_prefix.result
    
    key_vault_id = var.infra_vault_rid
}