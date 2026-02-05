terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
    }
  }
}

resource "digitalocean_droplet" "this" {
  name     = "sandbox-${var.name}"
  image    = "ubuntu-24-04-x64"
  size     = var.size
  region   = var.region
  vpc_uuid = var.vpc_uuid
  ssh_keys = [var.ssh_fingerprint]

  user_data = templatefile("${path.module}/cloud-init-worker.yml", {
    hub_ip         = var.hub_ip
    vpc_subnet     = var.vpc_subnet
    ssh_public_key = var.ssh_public_key
  })

  tags = ["sandbox", "worker"]
}
