# ──────────────────────────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────────────────────────

# ── VM IPs (from QEMU agent) ────────────────────────────────
output "k8s_master_ips" {
  description = "K8s control-plane IPs"
  value       = module.k8s_master1.ipv4_addresses
}

output "k8s_worker_ips" {
  description = "K8s worker IPs"
  value = {
    worker1 = module.k8s_worker1.ipv4_addresses
    worker2 = module.k8s_worker2.ipv4_addresses
  }
}

output "vault_ips" {
  description = "Vault cluster IPs"
  value = {
    vault1 = module.vault_1.ipv4_addresses
    vault2 = module.vault_2.ipv4_addresses
    vault3 = module.vault_3.ipv4_addresses
  }
}

# ── LXC Hostnames ────────────────────────────────────────────
output "edge_nodes" {
  description = "Edge LXC hostnames"
  value = {
    edge1 = module.edge_1.hostname
    edge2 = module.edge_2.hostname
  }
}
