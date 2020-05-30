remote_state {
  backend = "azurerm"
  config = {
    key            = "platformhub-${path_relative_to_include()}-terraform.tfstate"
    resource_group_name = "${get_env("TF_VAR_backend_storage_account_rg", "")}"
    storage_account_name = "${get_env("TF_VAR_backend_storage_account_name", "")}"
    container_name = "${get_env("TF_VAR_backend_container_name", "")}"
  }
}