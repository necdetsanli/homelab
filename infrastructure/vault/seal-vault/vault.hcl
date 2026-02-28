# Vault Seal Server — Transit Auto-Unseal Provider
# ─────────────────────────────────────────────────
# Dedicated Vault instance whose sole purpose is to provide the Transit
# engine for auto-unsealing the production 3-node Raft cluster.
#
# Host: vault-seal (192.168.20.28)
# Port: 8200
# Storage: file (single node, no HA needed)
# TLS: Vault root CA (same home-arpa-root-2025)
#
# This server must be on a DIFFERENT failure domain (different Proxmox host
# or physical node) from the production Vault cluster to survive correlated
# failures.  It should start before the production cluster on boot.
#
# Bootstrap:
#   1. Install Vault binary (same version as production)
#   2. Deploy this config to /etc/vault.d/vault.hcl
#   3. vault operator init -key-shares=1 -key-threshold=1
#      (single key is acceptable — this Vault protects only the Transit key,
#       not secrets.  Store the unseal key + root token in a secure offline
#       location: USB drive in a safe, password manager, etc.)
#   4. vault operator unseal <key>
#   5. Run setup commands from migration-runbook.md

ui = false

# ── Listener ─────────────────────────────────────────────────────────────
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_cert_file = "/opt/vault/tls/tls.crt"
  tls_key_file  = "/opt/vault/tls/tls.key"

  # Disable TLS client cert requirement (production Vault connects as client)
  tls_require_and_verify_client_cert = false
  tls_min_version = "tls13"
}

# ── Storage ──────────────────────────────────────────────────────────────
# File backend — simple, no HA.  Only stores the Transit encryption key.
storage "file" {
  path = "/opt/vault/data"
}

# ── Telemetry ────────────────────────────────────────────────────────────
telemetry {
  disable_hostname = true
  prometheus_retention_time = "12h"
}

# ── General ──────────────────────────────────────────────────────────────
api_addr     = "https://192.168.20.28:8200"
cluster_addr = "https://192.168.20.28:8201"

# Minimal log level
log_level = "warn"

# Disable mlock if running in a container or VM without IPC_LOCK capability
disable_mlock = true

# Max lease TTL (the Transit key has no lease, but set a sane default)
max_lease_ttl = "768h"
default_lease_ttl = "768h"
