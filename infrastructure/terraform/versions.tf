# ──────────────────────────────────────────────────────────────
# Terraform + Provider Version Pins
# ──────────────────────────────────────────────────────────────
# bpg/proxmox — full-featured community provider for PVE 8+
# https://registry.terraform.io/providers/bpg/proxmox/latest
# ──────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }
  }
}
