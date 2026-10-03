output "url" {
  description = "URL du site (HTTPS dispo 1-3 min apres l'apply, le temps que Caddy obtienne le certificat)"
  value       = "https://${local.fqdn}"
}

output "public_ip" {
  value = aws_eip.web.public_ip
}

output "ssm_connect" {
  description = "Shell sur l'instance sans SSH"
  value       = "aws ssm start-session --target ${aws_instance.web.id} --region ${var.aws_region}"
}
