variable "zone" {
  type        = string
  default     = "ru-central1-a"
}

variable "ansible_vault_path" {
  type        = string
  default     = "group_vars/all/vault.yml"
}

variable "token_ansible_vault_path" {
  type        = string
  default     = "group_vars/all/iam_token_vault.yml"
}
