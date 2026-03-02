# ──────────────────────────────────────────────────────────────
# LXC Module — Input Variables
# ──────────────────────────────────────────────────────────────

# ── Identity ─────────────────────────────────────────────────
variable "node_name" {
  description = "Proxmox node to deploy on"
  type        = string
}

variable "ctid" {
  description = "Container ID"
  type        = number
}

variable "hostname" {
  description = "Container hostname"
  type        = string
}

variable "description" {
  description = "Container description"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags for the container"
  type        = list(string)
  default     = []
}

# ── Lifecycle ────────────────────────────────────────────────
variable "on_boot" {
  description = "Start container on host boot"
  type        = bool
  default     = true
}

variable "started" {
  description = "Whether the container should be running"
  type        = bool
  default     = true
}

variable "startup_order" {
  description = "Boot order priority"
  type        = number
  default     = null
}

variable "startup_up_delay" {
  description = "Seconds delay after start"
  type        = number
  default     = 0
}

variable "startup_down_delay" {
  description = "Seconds delay after shutdown"
  type        = number
  default     = 0
}

# ── Security ─────────────────────────────────────────────────
variable "unprivileged" {
  description = "Run as unprivileged container"
  type        = bool
  default     = true
}

variable "nesting" {
  description = "Enable nesting (for Docker-in-LXC, etc.)"
  type        = bool
  default     = true
}

# ── Hardware ─────────────────────────────────────────────────
variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 1
}

variable "memory" {
  description = "RAM in MB"
  type        = number
  default     = 1024
}

variable "swap" {
  description = "Swap in MB"
  type        = number
  default     = 0
}

# ── Storage ──────────────────────────────────────────────────
variable "storage" {
  description = "Storage pool for rootfs"
  type        = string
  default     = "local-lvm"
}

variable "disk_size" {
  description = "Root filesystem size in GB"
  type        = number
  default     = 8
}

# ── OS Template ──────────────────────────────────────────────
variable "os_template" {
  description = "Container template file ID (e.g. local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst)"
  type        = string
}

variable "os_type" {
  description = "OS type (ubuntu, alpine, debian, etc.)"
  type        = string
  default     = "ubuntu"
}

# ── Network ──────────────────────────────────────────────────
variable "network_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "network_vlan" {
  description = "VLAN tag (null for untagged)"
  type        = number
  default     = null
}

variable "network_firewall" {
  description = "Enable Proxmox firewall on NIC"
  type        = bool
  default     = false
}

variable "network_dhcp" {
  description = "Use DHCP for IP configuration"
  type        = bool
  default     = true
}

variable "network_ip" {
  description = "Static IP in CIDR notation (when not using DHCP)"
  type        = string
  default     = ""
}

variable "network_gateway" {
  description = "Default gateway (when not using DHCP)"
  type        = string
  default     = ""
}

# ── DNS ──────────────────────────────────────────────────────
variable "dns_servers" {
  description = "DNS servers"
  type        = list(string)
  default     = []
}

variable "dns_domain" {
  description = "DNS search domain"
  type        = string
  default     = "home.arpa"
}

# ── Mount Points ─────────────────────────────────────────────
variable "mount_points" {
  description = "Additional mount points (bind mounts, USB, etc.)"
  type = list(object({
    volume = string
    path   = string
    shared = optional(bool, false)
  }))
  default = []
}
