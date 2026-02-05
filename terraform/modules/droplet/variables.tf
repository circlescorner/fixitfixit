variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "size" {
  type    = string
  default = "s-1vcpu-1gb"
}

variable "vpc_uuid" {
  type = string
}

variable "ssh_fingerprint" {
  type = string
}

variable "hub_ip" {
  type = string
}

variable "vpc_subnet" {
  type = string
}

variable "ssh_public_key" {
  type = string
}
