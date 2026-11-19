# Traduction de compose.staging.yaml : mêmes noms d'objets Docker.
locals {
  prefix      = "taskflow-${var.environment}"
  db_password = coalesce(var.db_password, random_password.db.result)
  db_url      = "postgres://taskflow:${local.db_password}@db:5432/taskflow"

  # Équivalent des ancres x-durcissement / x-sonde de Compose
  log_opts = { "max-size" = "10m", "max-file" = "3" }
  sonde    = { interval = "10s", timeout = "3s", retries = 5 }
}

# Il finit dans une URL : pas de caractères spéciaux.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "docker_network" "this" {
  name = local.prefix
}

resource "docker_volume" "pgdata" {
  name = "${local.prefix}-pgdata"

  # Volume créé par Compose (labels com.docker.compose.*) : ne pas le remplacer pour ça.
  lifecycle {
    ignore_changes = [labels]
  }
}

resource "docker_image" "db" {
  name         = "docker.io/library/postgres:16-alpine"
  keep_locally = true
}

resource "docker_image" "api" {
  name         = "ghcr.io/${var.ghcr_owner}/taskflow-api:${var.image_tag}"
  platform     = var.platform
  keep_locally = true
}

resource "docker_image" "front" {
  name         = "ghcr.io/${var.ghcr_owner}/taskflow-front:${var.image_tag}"
  platform     = var.platform
  keep_locally = true
}

resource "docker_container" "db" {
  name          = "${local.prefix}-db"
  image         = docker_image.db.image_id
  restart       = "unless-stopped"
  security_opts = ["no-new-privileges:true"]
  log_opts      = local.log_opts

  env = [
    "POSTGRES_USER=taskflow",
    "POSTGRES_DB=taskflow",
    "POSTGRES_PASSWORD=${local.db_password}",
  ]

  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name    = docker_network.this.name
    aliases = ["db"] # nom utilisé dans DATABASE_URL
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U taskflow -d taskflow"]
    interval = local.sonde.interval
    timeout  = local.sonde.timeout
    retries  = local.sonde.retries
  }

  # Équivalent de depends_on: condition: service_healthy
  wait         = true
  wait_timeout = 90
}

resource "docker_container" "api" {
  name          = "${local.prefix}-api"
  image         = docker_image.api.image_id
  restart       = "unless-stopped"
  security_opts = ["no-new-privileges:true"]
  log_opts      = local.log_opts

  env = [
    "PORT=3000",
    "APP_ENV=${var.environment}",
    "DATABASE_URL=${local.db_url}",
  ]

  networks_advanced {
    name    = docker_network.this.name
    aliases = ["api"] # nom utilisé par front/nginx.conf
  }

  healthcheck {
    test         = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:3000/health || exit 1"]
    interval     = local.sonde.interval
    timeout      = local.sonde.timeout
    retries      = local.sonde.retries
    start_period = "15s"
  }

  wait         = true
  wait_timeout = 90

  depends_on = [docker_container.db]
}

resource "docker_container" "front" {
  name          = "${local.prefix}-front"
  image         = docker_image.front.image_id
  restart       = "unless-stopped"
  security_opts = ["no-new-privileges:true"]
  log_opts      = local.log_opts

  ports {
    internal = 80
    external = var.front_port
  }

  networks_advanced {
    name = docker_network.this.name
  }

  healthcheck {
    test     = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1/ || exit 1"]
    interval = local.sonde.interval
    timeout  = local.sonde.timeout
    retries  = local.sonde.retries
  }

  depends_on = [docker_container.api]
}
