# ──────────────────────────────────────────────────────────────
# VM Module — Outputs
# ──────────────────────────────────────────────────────────────

output "vmid" {
  description = "The VM ID"
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  description = "The VM name"
  value       = proxmox_virtual_environment_vm.this.name
}

output "ipv4_addresses" {
  description = "IPv4 addresses reported by QEMU agent"
  value       = proxmox_virtual_environment_vm.this.ipv4_addresses
}

output "mac_addresses" {
  description = "MAC addresses of network interfaces"
  value       = proxmox_virtual_environment_vm.this.mac_addresses
}
