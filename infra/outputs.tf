output "url" {
  description = "Adresse du front"
  value       = "http://localhost:${var.front_port}"
}

output "health_url" {
  description = "Sonde de santé (via le front)"
  value       = "http://localhost:${var.front_port}/health"
}

output "image_tag" {
  description = "Version déployée"
  value       = var.image_tag
}

output "containers" {
  description = "Conteneurs gérés"
  value       = [docker_container.db.name, docker_container.api.name, docker_container.front.name]
}

output "network" {
  description = "Réseau Docker de l'environnement"
  value       = docker_network.this.name
}
