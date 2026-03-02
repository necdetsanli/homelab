# ──────────────────────────────────────────────────────────────
# LXC Module — Outputs
# ──────────────────────────────────────────────────────────────

output "ctid" {
  description = "The container ID"
  value       = proxmox_virtual_environment_container.this.vm_id
}

output "hostname" {
  description = "The container hostname"
  value       = var.hostname
}
