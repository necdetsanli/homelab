# Vault Transit Auto-Unseal — Migration Runbook
## Overview

Migrate the production 3-node Vault Raft cluster (192.168.20.25–27) from
**Shamir 5/3 seal** to **Transit auto-unseal** using a dedicated seal Vault
(192.168.20.28).

After migration, production Vault nodes automatically unseal on startup by
contacting the seal Vault's Transit engine — **zero manual intervention**.

**Estimated time:** 2–4 hours (including testing)  
**Downtime:** ~5 minutes per node during seal migration  
**Risk:** Low — migration is reversible (can revert to Shamir)

---

## Prerequisites

- [ ] Seal Vault VM provisioned at 192.168.20.28 (different Proxmox host)
- [ ] Vault binary installed on seal Vault (same version as production)
- [ ] TLS certificate for seal Vault issued (either Vault PKI or manual)
- [ ] Root CA (`home-arpa-root-2025`) available on all nodes at `/opt/vault/tls/ca.crt`
- [ ] All 3 production Vault nodes healthy and unsealed
- [ ] Current Shamir unseal keys accessible (need 3 of 5)

---

## Phase 1: Deploy and Initialize Seal Vault

### 1.1 Install Vault binary

```bash
ssh vault-seal  # 192.168.20.28

# Install HashiCorp repository
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vault
```

### 1.2 Deploy configuration

```bash
# Copy vault.hcl from infrastructure/vault/seal-vault/vault.hcl
sudo cp vault.hcl /etc/vault.d/vault.hcl
sudo chown vault:vault /etc/vault.d/vault.hcl

# Copy TLS cert + key
sudo mkdir -p /opt/vault/tls
sudo cp tls.crt /opt/vault/tls/tls.crt
sudo cp tls.key /opt/vault/tls/tls.key
sudo cp ca.crt /opt/vault/tls/ca.crt
sudo chown -R vault:vault /opt/vault/tls

# Copy systemd unit
sudo cp vault.service /etc/systemd/system/vault.service
sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault
```

### 1.3 Initialize seal Vault

```bash
export VAULT_ADDR="https://192.168.20.28:8200"
export VAULT_CACERT="/opt/vault/tls/ca.crt"

# Single key share — this Vault only protects the Transit encryption key
vault operator init -key-shares=1 -key-threshold=1

# SAVE THE OUTPUT SECURELY:
#   Unseal Key 1: <save-to-password-manager>
#   Initial Root Token: <save-to-password-manager>

vault operator unseal  # paste unseal key
```

### 1.4 Configure Transit engine

```bash
export VAULT_TOKEN="<root-token>"

# Enable Transit secrets engine
vault secrets enable transit

# Create the auto-unseal key (AES-256-GCM)
vault write -f transit/keys/vault-unseal \
  type=aes256-gcm96 \
  exportable=false \
  allow_plaintext_backup=false \
  deletion_allowed=false
```

### 1.5 Create AppRole for production Vault nodes

```bash
# Policy — minimum privilege: encrypt + decrypt only
vault policy write vault-unseal - <<'EOF'
path "transit/encrypt/vault-unseal" {
  capabilities = ["update"]
}
path "transit/decrypt/vault-unseal" {
  capabilities = ["update"]
}
EOF

# Enable AppRole auth method
vault auth enable approle

# Create role with periodic token (auto-renews, never expires while in use)
vault write auth/approle/role/vault-unseal \
  token_policies="vault-unseal" \
  token_type="service" \
  token_period="768h" \
  token_num_uses=0 \
  secret_id_num_uses=0 \
  secret_id_ttl=0

# Get role-id (static, safe to store on disk)
vault read -field=role_id auth/approle/role/vault-unseal/role-id
# OUTPUT: <role-id> → save this

# Generate secret-id (sensitive, deploy to each production node)
vault write -field=secret_id -f auth/approle/role/vault-unseal/secret-id
# OUTPUT: <secret-id> → save this

# TEST: Get a token using the AppRole
vault write auth/approle/login \
  role_id="<role-id>" \
  secret_id="<secret-id>"
# Verify the token has vault-unseal policy
```

---

## Phase 2: Pre-Migration Token Generation

Before migrating, generate a periodic token for the seal stanza.
The production Vault `seal "transit"` block needs a token to authenticate.

```bash
# On the seal Vault:
export VAULT_ADDR="https://192.168.20.28:8200"

# Login with AppRole to get a periodic service token
SEAL_TOKEN=$(vault write -field=token auth/approle/login \
  role_id="<role-id>" \
  secret_id="<secret-id>")

echo "VAULT_TRANSIT_SEAL_TOKEN=${SEAL_TOKEN}" | sudo tee /etc/vault.d/seal-env
sudo chmod 600 /etc/vault.d/seal-env
```

Deploy the token to each production node:

```bash
for node in 192.168.20.25 192.168.20.26 192.168.20.27; do
  ssh ${node} "echo 'VAULT_TRANSIT_SEAL_TOKEN=${SEAL_TOKEN}' | sudo tee /etc/vault.d/seal-env && sudo chmod 600 /etc/vault.d/seal-env && sudo chown vault:vault /etc/vault.d/seal-env"
done
```

---

## Phase 3: Seal Migration (Rolling, One Node at a Time)

**CRITICAL:** Migrate one node at a time. Keep 2/3 nodes unsealed at all times
to maintain Raft quorum.

### 3.1 Migrate the first node (vault-3, 192.168.20.27)

Start with a non-leader node to minimize risk.

```bash
ssh vault-3  # 192.168.20.27

# 1. Add the seal stanza to vault.hcl
# Copy infrastructure/vault/production/seal-transit.hcl content into vault.hcl
# The seal stanza must be added to the existing config.

# 2. Add EnvironmentFile to systemd unit
sudo systemctl edit vault
# Add:
#   [Service]
#   EnvironmentFile=/etc/vault.d/seal-env

# 3. Stop Vault on this node
sudo systemctl stop vault

# 4. Start with -migrate flag
sudo -u vault vault server -config=/etc/vault.d/vault.hcl -migrate &

# 5. Unseal with existing Shamir keys (3 of 5)
export VAULT_ADDR="https://192.168.20.27:8200"
vault operator unseal  # key 1
vault operator unseal  # key 2
vault operator unseal  # key 3

# The node will migrate its seal from Shamir to Transit.
# You should see: "seal migration complete"

# 6. Stop the migration process
kill %1

# 7. Start normally via systemd (should auto-unseal now)
sudo systemctl start vault

# 8. Verify it auto-unsealed
vault status
# Seal Type: transit
# Sealed: false  ← SUCCESS
```

### 3.2 Migrate vault-2 (192.168.20.26)

Repeat the exact same procedure on vault-2.

### 3.3 Migrate vault-1 (192.168.20.25, current leader)

The Raft leader will step down automatically when stopped. The other migrated
nodes will elect a new leader. Same procedure applies.

---

## Phase 4: Verification

```bash
# Check all nodes
for node in 192.168.20.25 192.168.20.26 192.168.20.27; do
  echo "=== ${node} ==="
  VAULT_ADDR="https://${node}:8200" vault status | grep -E "Seal Type|Sealed"
  echo
done

# Expected output for each:
#   Seal Type    transit
#   Sealed       false

# Test full cluster restart
for node in 192.168.20.25 192.168.20.26 192.168.20.27; do
  ssh ${node} "sudo systemctl restart vault"
done

# Wait 30 seconds, then verify all auto-unsealed
sleep 30
for node in 192.168.20.25 192.168.20.26 192.168.20.27; do
  echo "=== ${node} ==="
  VAULT_ADDR="https://${node}:8200" vault status | grep -E "Seal Type|Sealed"
done
```

---

## Phase 5: Post-Migration Hardening

### 5.1 Revoke Shamir recovery keys

After Transit auto-unseal, the original Shamir keys become **recovery keys**.
They can still perform `vault operator generate-root`. Store them securely
but they are no longer needed for day-to-day unsealing.

### 5.2 Set seal Vault to auto-start before production

Ensure Proxmox VM boot order: seal Vault → production Vault nodes.

```bash
# On Proxmox host, set VM boot order:
# seal-vault VM: boot order 1, startup delay 30s
# vault-1/2/3 VMs: boot order 2, startup delay 60s
qm set <seal-vault-vmid> --startup order=1,up=30
qm set <vault-1-vmid> --startup order=2,up=60
qm set <vault-2-vmid> --startup order=2,up=60
qm set <vault-3-vmid> --startup order=2,up=60
```

### 5.3 Monitor seal Vault health

Add the seal Vault to Zabbix monitoring. Alert if:
- Vault process is not running
- Port 8200 is not responding
- TLS certificate is expiring (< 30 days)

### 5.4 Backup the seal Vault

The Transit encryption key is the single most critical piece of data.
Without it, the production Vault cannot unseal.

```bash
# Periodic Raft snapshot (if using Raft) or file backup
# For file backend:
sudo tar czf /backup/vault-seal-$(date +%Y%m%d).tar.gz /opt/vault/data/
```

Store backups in at least 2 locations (e.g., TrueNAS + offline USB).

---

## Rollback Procedure

If Transit auto-unseal fails, revert to Shamir:

```bash
# On each production node:
# 1. Remove the seal "transit" stanza from vault.hcl
# 2. Start with -migrate flag
sudo -u vault vault server -config=/etc/vault.d/vault.hcl -migrate &
# 3. Unseal with recovery keys (formerly Shamir keys)
vault operator unseal  # recovery key 1
vault operator unseal  # recovery key 2
vault operator unseal  # recovery key 3
# 4. Seal migrates back to Shamir
```

---

## Architecture After Migration

```
┌─────────────────┐     Transit API     ┌────────────────────┐
│   Seal Vault    │◄────────────────────│  Production Vault  │
│  192.168.20.28  │   encrypt/decrypt   │  .25 / .26 / .27   │
│  (single node)  │   vault-unseal key  │  (3-node Raft)     │
│  file storage   │                     │  Raft storage      │
└─────────────────┘                     └────────────────────┘
      │                                        │
      │ AppRole auth                           │ K8s auth, PKI, KV
      │ (periodic token)                       │ (VSO, cert-manager)
      │                                        │
      ▼                                        ▼
  Auto-unseal on                          All homelab services
  every restart                           (no manual unseal!)
```
