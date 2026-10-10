output "oidc_provider_arn" {
  description = "ARN du fournisseur OIDC GitHub Actions"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "state_bucket" {
  description = "Nom du bucket S3 de state (a reporter dans la CI : -backend-config bucket=...)"
  value       = aws_s3_bucket.state.id
}

output "role_plan_arn" {
  description = "ARN du role PLAN -> variable GitHub AWS_ROLE_ARN_PLAN"
  value       = aws_iam_role.plan.arn
}

output "role_deploy_arn" {
  description = "ARN du role DEPLOY -> variable GitHub AWS_ROLE_ARN_DEPLOY"
  value       = aws_iam_role.deploy.arn
}
