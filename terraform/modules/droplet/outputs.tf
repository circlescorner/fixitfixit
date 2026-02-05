output "public_ip" {
  value = digitalocean_droplet.this.ipv4_address
}

output "private_ip" {
  value = digitalocean_droplet.this.ipv4_address_private
}
