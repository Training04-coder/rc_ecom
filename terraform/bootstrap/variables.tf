# Seules valeurs a renseigner par participant (dans terraform.tfvars).
# Tout le reste (bucket de state, ARN des roles, zone Route 53) en est deduit.

variable "aws_region" {
  description = "Region AWS du participant (ex: eu-west-1)"
  type        = string
  default     = "eu-west-1"
}

variable "github_owner" {
  description = "Compte ou organisation GitHub du participant (ex: participant-42)"
  type        = string
}

variable "github_repo" {
  description = "Nom du depot GitHub du participant, sans le owner (ex: bricoshop)"
  type        = string
}

variable "domain_name" {
  description = "Zone Route 53 publique existante dans le compte AWS du participant (ex: participant42.click)"
  type        = string
}

variable "subdomain" {
  description = "Sous-domaine du site (app => app.<domain_name>)"
  type        = string
  default     = "app"
}

variable "create_oidc_provider" {
  description = "false si le compte AWS possede deja un fournisseur OIDC token.actions.githubusercontent.com"
  type        = bool
  default     = true
}
