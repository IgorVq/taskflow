terraform {
  required_version = ">= 1.6.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Chemin du state donné à l'init, hors du dépôt :
  #   tofu init -backend-config="path=$STAGING_DIR/terraform.tfstate"
  backend "local" {}
}
