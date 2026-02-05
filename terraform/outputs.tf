output "hub_ip" {
  description = "Public IP of the always‑on hub"
  value       = digitalocean_droplet.hub.ipv4_address
}

output "hub_private_ip" {
  description = "VPC‑internal IP of the hub"
  value       = digitalocean_droplet.hub.ipv4_address_private
}

output "vpc_id" {
  value = digitalocean_vpc.sandbox.id
}

output "dashboard_url" {
  value = "https://${var.domain}"
}

output "extra_droplets" {
  description = "IPs of on‑demand droplets"
  value = {
    for k, v in module.extra_droplet : k => {
      public_ip  = v.public_ip
      private_ip = v.private_ip
    }
  }
}
