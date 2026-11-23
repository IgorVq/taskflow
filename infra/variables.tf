variable "ghcr_owner" {
  description = "Propriétaire des images sur ghcr.io (en minuscules)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.ghcr_owner))
    error_message = "ghcr_owner : minuscules, chiffres et tirets uniquement."
  }
}

variable "image_tag" {
  description = "Tag des images api et front (SHA court ou latest)"
  type        = string
  default     = "latest"

  validation {
    condition     = can(regex("^([0-9a-f]{7}|latest)$", var.image_tag))
    error_message = "image_tag : SHA court (7 caractères hexadécimaux) ou « latest »."
  }
}

variable "front_port" {
  description = "Port publié du front sur le poste"
  type        = number
  default     = 8081

  validation {
    condition     = var.front_port >= 1024 && var.front_port <= 65535
    error_message = "front_port doit être entre 1024 et 65535."
  }
}

variable "environment" {
  description = "Nom de l'environnement (préfixe des objets Docker, APP_ENV)"
  type        = string
  default     = "staging"
}

variable "platform" {
  description = "Plateforme des images (celle construite par la CI)"
  type        = string
  default     = "linux/amd64"
}

variable "db_password" {
  description = "Mot de passe PostgreSQL ; null = généré par random_password"
  type        = string
  default     = null
  sensitive   = true
}

variable "ghcr_username" {
  description = "Utilisateur ghcr.io (paquets privés)"
  type        = string
  default     = null
}

variable "ghcr_token" {
  description = "Jeton ghcr.io avec read:packages (paquets privés)"
  type        = string
  default     = null
  sensitive   = true
}
