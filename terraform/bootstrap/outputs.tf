# A recopier tel quel dans GitHub : Settings > Secrets and variables > Actions > Variables
output "github_variables" {
  description = "Variables GitHub Actions a creer (nom = valeur)"
  value = {
    AWS_ACCOUNT_ID = local.account_id
    AWS_REGION     = var.aws_region
    DOMAIN_NAME    = var.domain_name
    SUBDOMAIN      = var.subdomain
  }
}

output "github_environment" {
  description = "Environnement GitHub a creer (avec required reviewers)"
  value       = local.environment
}

output "site_url" {
  description = "URL du site une fois le pipeline passe"
  value       = "https://${var.subdomain}.${var.domain_name}"
}

# Uniquement pour lancer le Terraform principal depuis ta machine (facultatif).
output "local_init_command" {
  description = "Commande d'init du Terraform principal (dossier terraform/) en local"
  value       = "terraform init -backend-config=\"bucket=${aws_s3_bucket.state.id}\" -backend-config=\"region=${var.aws_region}\""
}

output "role_plan_arn" {
  value = aws_iam_role.plan.arn
}

output "role_deploy_arn" {
  value = aws_iam_role.deploy.arn
}
