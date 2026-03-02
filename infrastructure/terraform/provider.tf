# ──────────────────────────────────────────────────────────────
# Provider Configuration
# ──────────────────────────────────────────────────────────────
# Auth: export PROXMOX_VE_API_TOKEN="terraform@pam!homelab=<secret>"
#   or: set via variables below
# ──────────────────────────────────────────────────────────────

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  ssh {
    agent    = true
    username = var.proxmox_ssh_user
  }
}
