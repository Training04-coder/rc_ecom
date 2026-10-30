# Backend S3 distant, partage entre la CI et la machine du participant.
# Configuration PARTIELLE : le bucket depend de l'ID du compte AWS, il est fourni
# au `terraform init` (le workflow le fait automatiquement) :
#
#   terraform init -backend-config="bucket=rch-bricoshop-tfstate-<account_id>"
#
# Region (forcee eu-west-1) et cle sont fixees ici. Bucket et cle doivent rester
# alignes avec terraform/bootstrap (local.state_bucket) et .github/workflows/deploy.yml.
# Le bootstrap affiche la commande toute prete (output local_init_command).
terraform {
  backend "s3" {
    key          = "rch-bricoshop/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true # verrou natif S3 (Terraform >= 1.10)
  }
}
