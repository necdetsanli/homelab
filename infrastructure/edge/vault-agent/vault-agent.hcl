# =============================================================================
# Vault Agent — edge node secret delivery
#
# Authenticates to Vault via AppRole, renders keepalived.conf from a Go
# template that injects the VRRP auth_pass from KV v2. Re-renders every
# 5 minutes and on SIGHUP (sent by edge-gitops-sync when templates change).
#
# Deployed to: /etc/vault-agent/vault-agent.hcl
#
# ── One-time bootstrap (on Vault server) ─────────────────────────────────────
#
#   # 1. Create policy
#   vault policy write edge-keepalived - <<'EOF'
#   path "secret/data/edge/keepalived" {
#     capabilities = ["read"]
#   }
#   EOF
#
#   # 2. Enable AppRole (skip if already enabled)
#   vault auth enable approle
#
#   # 3. Create role (no secret_id expiry — long-lived edge nodes)
#   vault write auth/approle/role/edge-keepalived \
#     token_policies="edge-keepalived" \
#     token_ttl=1h \
#     token_max_ttl=4h \
#     secret_id_ttl=0 \
#     token_num_uses=0
#
#   # 4. Retrieve role_id (same for both nodes)
#   vault read -field=role_id auth/approle/role/edge-keepalived/role-id
#
#   # 5. Generate per-node secret_id (one per edge node for audit trail)
#   vault write -f -field=secret_id auth/approle/role/edge-keepalived/secret-id
#
#   # 6. Seed the VRRP password into KV
#   vault kv put secret/edge/keepalived vrrp_pass="$(openssl rand -hex 8)"
#
# ── One-time bootstrap (on each edge node, as root) ──────────────────────────
#
#   install -d -m 0750 /etc/vault-agent
#   echo "<role_id>"   > /etc/vault-agent/role-id
#   echo "<secret_id>" > /etc/vault-agent/secret-id
#   chmod 0640 /etc/vault-agent/role-id /etc/vault-agent/secret-id
#   systemctl enable --now vault-agent
#
# =============================================================================

vault {
  address = "https://vault.home.arpa"
  # TLS verification uses the system CA trust store.
  # The home-arpa root CA must be installed in /usr/local/share/ca-certificates/
  # and update-ca-certificates run (already required for certbot ACME).
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path                 = "/etc/vault-agent/role-id"
      secret_id_file_path               = "/etc/vault-agent/secret-id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/etc/vault-agent/token"
      mode = 0640
    }
  }
}

template_config {
  exit_on_retry_failure        = true
  static_secret_render_interval = "5m"
}

template {
  source      = "/etc/keepalived/keepalived.conf.ctmpl"
  destination = "/etc/keepalived/keepalived.conf"
  perms       = "0640"
  command     = "systemctl reload keepalived 2>/dev/null || true"
  error_on_missing_key = true
}
