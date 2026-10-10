# Backend S3 distant, partage entre la CI et la machine du participant.
# Configuration PARTIELLE : bucket et region sont propres a chaque compte AWS,
# ils sont fournis au `terraform init` (le workflow le fait automatiquement) :
#
#   terraform init -backend-config="bucket=bricoshop-tfstate-<account_id>" \
#                  -backend-config="region=<region>"
#
# Le bootstrap affiche cette commande toute prete (output local_init_command).
terraform {
  backend "s3" {
    key          = "bricoshop/terraform.tfstate"
    encrypt      = true
    use_lockfile = true # verrou natif S3 (Terraform >= 1.10)
  }
}
