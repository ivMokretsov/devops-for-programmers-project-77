terraform {
  required_providers {
    ansiblevault = {
      source  = "meilleursagents/ansiblevault"
      version = "2.3.0"
    }
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.121.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.1"
    }
  }
}

provider "ansiblevault" {
  vault_path = "../.vault_pass"
  root_folder         = "../ansible"
}

data "ansiblevault_path" "cloud_id" {
  path = var.ansible_vault_path
  key = "cloud_id"
}

data "ansiblevault_path" "folder_id" {
  path = var.ansible_vault_path
  key = "folder_id"
}

data "ansiblevault_path" "token" {
  path = var.token_ansible_vault_path
  key = "token"
}

provider "yandex" {
  token     = data.ansiblevault_path.token.value
  cloud_id  = data.ansiblevault_path.cloud_id.value
  folder_id = data.ansiblevault_path.folder_id.value
  zone      = var.zone
}
