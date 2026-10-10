terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # State LOCAL volontaire : le bootstrap cree le bucket du state distant, il ne
  # peut donc pas y stocker son propre state. Le terraform.tfstate genere ici est
  # ignore par git (.gitignore) : le garder sur la machine du participant.
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
