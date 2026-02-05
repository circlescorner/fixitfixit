variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "nyc1"
}

variable "hub_size" {
  description = "Droplet size for the always‑on hub"
  type        = string
  default     = "s-1vcpu-1gb"
}

variable "domain" {
  description = "Root domain for the sandbox (e.g. sandbox.example.com)"
  type        = string
}

variable "admin_email" {
  description = "Email for Let's Encrypt & Authelia admin"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "manage_dns" {
  description = "Let Terraform manage DNS via DigitalOcean"
  type        = bool
  default     = false
}

variable "authelia_jwt_secret" {
  description = "JWT secret for Authelia (generate with: openssl rand -hex 32)"
  type        = string
  sensitive   = true
}

variable "extra_droplets" {
  description = "Map of on‑demand droplets to provision"
  type = map(object({
    size = string
  }))
  default = {}
}
