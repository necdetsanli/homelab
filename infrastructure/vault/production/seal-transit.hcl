# Vault Transit Auto-Unseal — Seal Stanza for Production Vault
# ──────────────────────────────────────────────────────────────
# Add this stanza to each production Vault node's vault.hcl AFTER the
# seal migration procedure is complete (see migration-runbook.md).
#
# This replaces the default Shamir seal.  On startup, each production
# node contacts the seal Vault at 192.168.20.28 to decrypt its master key
# via the Transit engine — no manual unseal operations required.
#
# The AppRole credentials (role_id + secret_id) are deployed to each
# production node at /etc/vault.d/seal-role-id and /etc/vault.d/seal-secret-id.

seal "transit" {
  address         = "https://192.168.20.28:8200"
  disable_renewal = false

  # Transit engine mount and key name on the seal Vault
  mount_path = "transit/"
  key_name   = "vault-unseal"

  # AppRole authentication to the seal Vault
  token = ""  # Left empty — use environment variable VAULT_SEAL_TOKEN or file-based approach below

  # TLS — verify the seal Vault's certificate using the shared root CA
  tls_ca_cert = "/opt/vault/tls/ca.crt"
  tls_skip_verify = false
}

# ── Alternative: Environment-based token ─────────────────────────────────
# Instead of hardcoding a token, use a wrapper script or systemd override:
#
#   [Service]
#   EnvironmentFile=/etc/vault.d/seal-env
#
# Where /etc/vault.d/seal-env contains:
#   VAULT_TRANSIT_SEAL_TOKEN=<periodic-token>
#
# The seal stanza then becomes:
#   seal "transit" {
#     ...
#     token = ""  # reads from VAULT_TRANSIT_SEAL_TOKEN env var
#   }
