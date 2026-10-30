# Seules valeurs a renseigner par participant (dans terraform.tfvars) : github_owner
# et github_repo. Initiales, region et domaine ont des valeurs par defaut forcees.
# Tout le reste (bucket de state, ARN des roles, zone Route 53) en est deduit.

variable "initials" {
  description = "Initiales du participant, prefixe de chaque nom de ressource (minuscules/chiffres)"
  type        = string
  default     = "rch"
  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.initials))
    error_message = "initials : 2 a 6 caracteres minuscules ou chiffres (contrainte des noms S3)."
  }
}

variable "aws_region" {
  description = "Region AWS (forcee : eu-west-1)"
  type        = string
  default     = "eu-west-1"
  validation {
    condition     = var.aws_region == "eu-west-1"
    error_message = "La region est forcee a eu-west-1."
  }
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
  description = "Zone Route 53 publique existante dans le compte AWS du participant (ex: alpha-awslab26.click)"
  type        = string
  default     = "alpha-awslab26.click"
}

variable "subdomain" {
  description = "Sous-domaine du site (rch => rch.<domain_name>)"
  type        = string
  default     = "rch"
}

variable "create_oidc_provider" {
  description = "false si le compte AWS possede deja un fournisseur OIDC token.actions.githubusercontent.com"
  type        = bool
  default     = true
}
