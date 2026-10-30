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
  description = "Region AWS de deploiement (forcee : eu-west-1)"
  type        = string
  default     = "eu-west-1"
  validation {
    condition     = var.aws_region == "eu-west-1"
    error_message = "La region est forcee a eu-west-1."
  }
}

variable "domain_name" {
  description = "Zone hebergee Route 53 PUBLIQUE existante (ex: alpha-awslab26.click)"
  type        = string
  default     = "alpha-awslab26.click"
}

variable "subdomain" {
  description = "Sous-domaine du site (ex: rch => rch.alpha-awslab26.click)"
  type        = string
  default     = "rch"
}

variable "instance_type" {
  description = "Type d'instance EC2"
  type        = string
  default     = "t3.micro"
}

variable "demo_vuln" {
  description = "true = active une XSS volontaire sur /search pour que Security Agent ait quelque chose a trouver"
  type        = bool
  default     = false
}
