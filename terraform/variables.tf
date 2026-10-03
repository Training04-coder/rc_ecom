variable "aws_region" {
  description = "Region AWS de deploiement"
  type        = string
  default     = "eu-west-3"
}

variable "domain_name" {
  description = "Zone hebergee Route 53 PUBLIQUE existante (ex: mondomaine.click)"
  type        = string
}

variable "subdomain" {
  description = "Sous-domaine du site (ex: app => app.mondomaine.click)"
  type        = string
  default     = "app"
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
