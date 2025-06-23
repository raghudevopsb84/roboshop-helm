provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

provider "azurerm" {
  features {}
  subscription_id = "323379f3-3beb-4865-821e-0fff68e4d4ca"
}

terraform {
  backend "azurerm" {}
}