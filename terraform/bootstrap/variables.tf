variable "aws_region" {
  description = "Region AWS (doit correspondre a celle du Terraform principal)"
  type        = string
  default     = "eu-west-1"
}

variable "github_org" {
  description = "Organisation ou compte GitHub proprietaire du depot"
  type        = string
  default     = "lims931"
}

variable "github_repo" {
  description = "Nom du depot GitHub (sans l'org)"
  type        = string
  default     = "secagent-lab-beautify"
}

variable "github_environment" {
  description = "Nom de l'environnement GitHub autorise a deployer (condition sub du role deploy)"
  type        = string
  default     = "production"
}

variable "state_bucket_name" {
  description = <<-EOT
    Nom GLOBALEMENT unique du bucket S3 qui stockera le state Terraform.
    Laisser vide pour utiliser "<org>-<repo>-tfstate" (en minuscules).
    Cette valeur doit etre reportee dans la CI (-backend-config bucket=...).
  EOT
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = <<-EOT
    (Optionnel) ID de la zone Route 53 publique geree par le Terraform principal.
    Si fourni, les droits route53:ChangeResourceRecordSets du role deploy y sont
    restreints. Laisser vide pour autoriser toutes les zones du compte.
  EOT
  type        = string
  default     = ""
}

variable "managed_resource_prefix" {
  description = "Prefixe des noms de ressources crees par le Terraform principal (name_prefix / bucket_prefix)"
  type        = string
  default     = "secagent-java-"
}

variable "app_log_group_name" {
  description = "Nom du log group CloudWatch gere par le Terraform principal"
  type        = string
  default     = "/bricoshop/app"
}
