terraform {
  required_version = ">= 1.5"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.34"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

# -------------------------------------------------------------------
# VPC — all resources (hub + on‑demand droplets) share this network
# -------------------------------------------------------------------
resource "digitalocean_vpc" "sandbox" {
  name     = "sandbox-vpc"
  region   = var.region
  ip_range = "10.100.0.0/16"
}

# -------------------------------------------------------------------
# SSH key
# -------------------------------------------------------------------
resource "digitalocean_ssh_key" "default" {
  name       = "sandbox-key"
  public_key = file(var.ssh_public_key_path)
}

# -------------------------------------------------------------------
# Firewall — allow SSH, HTTP, HTTPS + internal VPC traffic
# -------------------------------------------------------------------
resource "digitalocean_firewall" "sandbox" {
  name = "sandbox-fw"

  droplet_ids = [digitalocean_droplet.hub.id]

  # Inbound
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  # VPC internal — all ports
  inbound_rule {
    protocol         = "tcp"
    port_range       = "1-65535"
    source_addresses = [digitalocean_vpc.sandbox.ip_range]
  }
  inbound_rule {
    protocol         = "udp"
    port_range       = "1-65535"
    source_addresses = [digitalocean_vpc.sandbox.ip_range]
  }
  inbound_rule {
    protocol         = "icmp"
    source_addresses = [digitalocean_vpc.sandbox.ip_range]
  }

  # Outbound — allow all
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# -------------------------------------------------------------------
# Always‑on hub droplet  (s‑1vcpu‑1gb = smallest)
# -------------------------------------------------------------------
resource "digitalocean_droplet" "hub" {
  name     = "sandbox-hub"
  image    = "ubuntu-24-04-x64"
  size     = var.hub_size
  region   = var.region
  vpc_uuid = digitalocean_vpc.sandbox.id
  ssh_keys = [digitalocean_ssh_key.default.fingerprint]

  user_data = templatefile("${path.module}/../infra/cloud-init.yml", {
    domain          = var.domain
    admin_email     = var.admin_email
    do_token        = var.do_token
    vpc_subnet      = digitalocean_vpc.sandbox.ip_range
    authelia_secret = var.authelia_jwt_secret
    ssh_public_key  = file(var.ssh_public_key_path)
  })

  tags = ["sandbox", "hub"]
}

# -------------------------------------------------------------------
# DNS — point domain at the hub (optional, requires DO DNS)
# -------------------------------------------------------------------
resource "digitalocean_domain" "sandbox" {
  count = var.manage_dns ? 1 : 0
  name  = var.domain
}

resource "digitalocean_record" "hub_a" {
  count  = var.manage_dns ? 1 : 0
  domain = digitalocean_domain.sandbox[0].id
  type   = "A"
  name   = "@"
  value  = digitalocean_droplet.hub.ipv4_address
  ttl    = 300
}

resource "digitalocean_record" "wildcard" {
  count  = var.manage_dns ? 1 : 0
  domain = digitalocean_domain.sandbox[0].id
  type   = "A"
  name   = "*"
  value  = digitalocean_droplet.hub.ipv4_address
  ttl    = 300
}

# -------------------------------------------------------------------
# On‑demand droplet module (called from dashboard API)
# -------------------------------------------------------------------
module "extra_droplet" {
  source   = "./modules/droplet"
  for_each = var.extra_droplets

  name            = each.key
  region          = var.region
  size            = each.value.size
  vpc_uuid        = digitalocean_vpc.sandbox.id
  ssh_fingerprint = digitalocean_ssh_key.default.fingerprint
  hub_ip          = digitalocean_droplet.hub.ipv4_address
  vpc_subnet      = digitalocean_vpc.sandbox.ip_range
  ssh_public_key  = file(var.ssh_public_key_path)
}
