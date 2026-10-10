terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # State LOCAL volontaire : le bootstrap cree le bucket de state distant,
  # il ne peut donc pas y stocker son propre state (l'oeuf et la poule).
  # On applique ce dossier une seule fois en local, et on commite le
  # terraform.tfstate du bootstrap n'est PAS necessaire (ressources rarement modifiees).
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project = "secagent-java-lab"
      Owner   = "formation"
      Usage   = "ci-bootstrap"
    }
  }
}
