# ──────────────────────────────────────────────────────────────
# VM Module — Input Variables
# ──────────────────────────────────────────────────────────────

# ── Identity ─────────────────────────────────────────────────
variable "node_name" {
  description = "Proxmox node to deploy on"
  type        = string
}

variable "vmid" {
  description = "VM ID"
  type        = number
}

variable "name" {
  description = "VM name"
  type        = string
}

variable "description" {
  description = "VM description"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags for the VM"
  type        = list(string)
  default     = []
}

# ── Lifecycle ────────────────────────────────────────────────
variable "on_boot" {
  description = "Start VM on host boot"
  type        = bool
  default     = true
}

variable "started" {
  description = "Whether the VM should be running"
  type        = bool
  default     = true
}

variable "startup_order" {
  description = "Boot order priority (lower = earlier)"
  type        = number
  default     = null
}

variable "startup_up_delay" {
  description = "Seconds to wait after starting before next VM"
  type        = number
  default     = 0
}

variable "startup_down_delay" {
  description = "Seconds to wait after shutdown before next VM"
  type        = number
  default     = 0
}

# ── Hardware ─────────────────────────────────────────────────
variable "machine" {
  description = "Machine type (q35 or i440fx)"
  type        = string
  default     = "q35"
}

variable "bios" {
  description = "BIOS type (seabios or ovmf)"
  type        = string
  default     = "seabios"
}

variable "cpu_type" {
  description = "CPU type"
  type        = string
  default     = "host"
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "sockets" {
  description = "Number of CPU sockets"
  type        = number
  default     = 1
}

variable "memory" {
  description = "RAM in MB"
  type        = number
  default     = 2048
}

variable "agent_enabled" {
  description = "Enable QEMU guest agent"
  type        = bool
  default     = true
}

variable "boot_order" {
  description = "Boot device order"
  type        = list(string)
  default     = ["scsi0"]
}

# ── Storage ──────────────────────────────────────────────────
variable "storage" {
  description = "Storage pool for disks"
  type        = string
  default     = "local-lvm"
}

variable "disk_size" {
  description = "Primary disk size in GB"
  type        = number
  default     = 32
}

variable "disk_ssd" {
  description = "Emulate SSD"
  type        = bool
  default     = true
}

variable "disk_discard" {
  description = "Enable discard/TRIM"
  type        = bool
  default     = true
}

variable "additional_disks" {
  description = "Additional disks"
  type = list(object({
    interface = string
    size      = number
    storage   = string
    ssd       = optional(bool, true)
    discard   = optional(bool, true)
  }))
  default = []
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

variable "additional_nics" {
  description = "Additional network interfaces"
  type = list(object({
    bridge   = string
    vlan_id  = optional(number)
    firewall = optional(bool, false)
  }))
  default = []
}

# ── PCI Passthrough ──────────────────────────────────────────
variable "pci_devices" {
  description = "PCI devices to pass through"
  type = list(object({
    device = string
    id     = string
    pcie   = optional(bool, false)
    rombar = optional(bool, true)
  }))
  default = []
}

# ── Display ──────────────────────────────────────────────────
variable "os_type" {
  description = "OS type hint (l26, win11, other)"
  type        = string
  default     = "l26"
}

variable "vga_type" {
  description = "VGA adapter type"
  type        = string
  default     = "std"
}

variable "serial_enabled" {
  description = "Enable serial console"
  type        = bool
  default     = false
}

# ── Cloud-Init ───────────────────────────────────────────────
variable "cloud_init_enabled" {
  description = "Enable cloud-init configuration"
  type        = bool
  default     = false
}

variable "cloud_init_ip" {
  description = "Static IP in CIDR notation (e.g. 192.168.20.20/24)"
  type        = string
  default     = ""
}

variable "cloud_init_gateway" {
  description = "Default gateway"
  type        = string
  default     = ""
}

variable "cloud_init_dns" {
  description = "DNS servers"
  type        = list(string)
  default     = []
}

variable "cloud_init_domain" {
  description = "Search domain"
  type        = string
  default     = "home.arpa"
}

variable "cloud_init_user" {
  description = "Default user"
  type        = string
  default     = "necdetsanli"
}

variable "cloud_init_ssh_keys" {
  description = "SSH public keys"
  type        = list(string)
  default     = []
}
