# Backend S3 distant pour partager le state entre ta machine et la CI.
# Configuration PARTIELLE : le nom du bucket (cree par terraform/bootstrap/) est
# fourni au moment du `terraform init` via -backend-config, pour ne coder en dur
# aucune valeur specifique a un compte dans le depot.
#
#   terraform init \
#     -backend-config="bucket=<state_bucket du bootstrap>" \
#     -migrate-state        # la 1re fois seulement, pour pousser le state local
#
# Voir docs/ci-cd.md.
terraform {
  backend "s3" {
    key     = "secagent-lab-beautify/terraform.tfstate"
    region  = "eu-west-1"
    encrypt = true
  }
}
