# Lit DOCKER_HOST s'il est défini, sinon /var/run/docker.sock.
provider "docker" {
  # Authentification ghcr.io seulement si un jeton est fourni (non écrit dans le state).
  dynamic "registry_auth" {
    for_each = var.ghcr_token == null ? [] : [1]
    content {
      address  = "ghcr.io"
      username = var.ghcr_username
      password = var.ghcr_token
    }
  }
}
