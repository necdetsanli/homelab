# ──────────────────────────────────────────────────────────────
# Input Variables
# ──────────────────────────────────────────────────────────────

# ── Provider Auth ────────────────────────────────────────────
variable "proxmox_endpoint" {
  description = "Proxmox VE API URL"
  type        = string
  default     = "https://192.168.50.2:8006"
}

variable "proxmox_api_token" {
  description = "API token in format user@realm!tokenid=secret"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (self-signed cert)"
  type        = bool
  default     = true
}

variable "proxmox_ssh_user" {
  description = "SSH user for provider file operations"
  type        = string
  default     = "root"
}

# ── Target Node ──────────────────────────────────────────────
variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "proxmox"
}

# ── Common Defaults ──────────────────────────────────────────
variable "default_storage" {
  description = "Default storage pool for VM/LXC disks"
  type        = string
  default     = "local-lvm"
}

variable "default_bridge" {
  description = "Default network bridge"
  type        = string
  default     = "vmbr0"
}

variable "server_vlan_id" {
  description = "VLAN tag for server network"
  type        = number
  default     = 20
}

variable "mgmt_vlan_id" {
  description = "VLAN tag for management network"
  type        = number
  default     = 50
}

# ── SSH Keys ─────────────────────────────────────────────────
variable "ssh_public_keys" {
  description = "SSH public keys to inject via cloud-init"
  type        = list(string)
  default     = []
}

variable "default_user" {
  description = "Default cloud-init user"
  type        = string
  default     = "necdetsanli"
}
