# Edge Reverse-Proxy Tier

Two Ubuntu VMs running **HAProxy + Keepalived** in active/passive with a
floating VIP. No services are exposed to the internet — all access is
restricted to specific hosts on specific VLANs (management, client, WireGuard).

All configuration is managed via **GitOps** — push to `main` and each edge
node auto-deploys within 5 minutes.

## Topology

```
Internal VLAN clients / WireGuard peers
                │
                ▼
  ┌───────────────────────────────┐
  │  VIP  192.168.20.22  (VRRP)  │
  │  ┌─────────┐   ┌─────────┐   │
  │  │ edge-1  │   │ edge-2  │   │
  │  │ .20.20  │   │ .20.21  │   │
  │  │ MASTER  │   │ BACKUP  │   │
  │  └─────────┘   └─────────┘   │
  └───────────────────────────────┘
        │                   │
        ▼                   ▼
   ┌─────────────────────────────────────────────┐
   │  Backend Services                           │
   │  ├─ Appliances (OPNsense, Proxmox, …)      │
   │  ├─ Vault cluster (active-node routing)     │
   │  └─ K8s Gateway API (Cilium Envoy)          │
   │     ├─ longhorn.mgmt.home.arpa → Longhorn   │
   │     └─ hubble.mgmt.home.arpa  → Hubble UI   │
   └─────────────────────────────────────────────┘
```

## Components

| Component        | Version  | Purpose                                                               |
| ---------------- | -------- | --------------------------------------------------------------------- |
| HAProxy          | 2.8 LTS  | TLS termination, SNI routing, health checks, TLS re-encryption       |
| Keepalived       | 2.x      | VRRP failover, VIP management, certsync trigger on transition        |
| certbot          | latest   | ACME client for Vault PKI DNS-01 cert issuance                       |
| edge-gitops-sync | —        | Pull-based GitOps config deployment from GitHub (5-min poll)         |

## DNS Zones

| Zone               | Access                               | Examples                                     |
| ------------------ | ------------------------------------ | -------------------------------------------- |
| `*.app.home.arpa`  | All VLANs                            | `nextcloud.app.home.arpa`                    |
| `*.mgmt.home.arpa` | WireGuard only (`10.66.66.2/32`)     | `opnsense.mgmt.home.arpa`, `hubble.mgmt.home.arpa` |
| `vault.home.arpa`  | Mgmt + Client VLANs + K8s pod CIDR  | Vault API (active-node routing)              |

## File Layout

```
infrastructure/edge/
├── README.md
├── haproxy/
│   ├── haproxy.cfg                             # Shared config (identical on both nodes)
│   └── certsync/
│       ├── crt-list.txt                        # Seed template (auto-generated at runtime)
│       └── allowlist.txt                       # Seed template (auto-generated at runtime)
├── keepalived/
│   ├── edge-1-keepalived.conf                  # MASTER  priority 120
│   ├── edge-2-keepalived.conf                  # BACKUP  priority 110
│   └── scripts/
│       └── keepalived-notify-certsync.sh       # VIP transition → cert sync trigger
├── certbot/
│   ├── dns01/
│   │   ├── auth.sh                             # DNS-01 auth hook (nsupdate / GSS-TSIG)
│   │   └── cleanup.sh                          # DNS-01 cleanup hook (delete TXT record)
│   ├── hooks/
│   │   └── deploy/
│   │       └── 50-haproxy-deploy               # Renewal hook: PEM assembly + reload
│   └── systemd/
│       ├── vault-acme-issue-all.timer          # Daily renewal timer (03:17 + 1h jitter)
│       ├── vault-acme-issue-all.service        # One-shot: runs the cert orchestrator
│       └── vault-acme-issue-all.service.d/
│           └── 20-certsync.conf                # Drop-in: ExecStartPost → haproxy-certs-send
├── gitops/
│   ├── edge-gitops-sync.sh                     # GitOps pull + deploy script
│   ├── edge-gitops-sync.service                # systemd one-shot (flock protected)
│   └── edge-gitops-sync.timer                  # 5-minute poll timer
└── scripts/
    ├── vault-acme-issue-all.sh                 # Self-provisioning cert orchestrator
    ├── haproxy-certs-send                      # rsync PEMs + config → edge-2 (certsync user)
    └── haproxy-certs-recv                      # rsync receiver on edge-2 (ForceCommand)
```

## GitOps Config Sync

Edge node configs are automatically synced from this GitHub repo via
`edge-gitops-sync.sh`. Each node independently pulls the repo every 5 minutes,
compares HEAD against the last-deployed commit, and deploys only changed files
with correct ownership/permissions.

```
edge-gitops-sync.timer (every 5 min, OnBootSec=60s)
  → edge-gitops-sync.service (flock protected against concurrent runs)
    → edge-gitops-sync.sh
      1. git fetch --depth 1 origin main && git reset --hard
      2. diff HEAD vs last-deployed commit (stored in state file)
      3. deploy changed files to system paths (atomic mv, chown, chmod)
      4. systemctl daemon-reload (if systemd units changed)
      5. haproxy -c + reload/restart (if HAProxy files changed)
         └─ pre-flight: verify ALL PEMs in crt-list exist before reload
      6. keepalived reload (if keepalived.conf changed)
      7. haproxy-certs-send (VIP owner only, if HAProxy files changed)
      8. save deployed commit to state file
```

**Key properties:**
- **Self-updating**: the sync script + its own systemd units are in the manifest
- **Idempotent**: skips files where destination content is identical
- **Safe**: pre-flight PEM check prevents HAProxy from failing on missing certs
- **Concurrency-safe**: `flock` prevents overlapping runs during fast git pushes

**File manifest** (16 shared entries + 1 per-hostname keepalived config):

| Source (repo)                                         | Destination (system)                                     | Service tag |
| ----------------------------------------------------- | -------------------------------------------------------- | ----------- |
| `haproxy/haproxy.cfg`                                  | `/etc/haproxy/haproxy.cfg`                               | haproxy     |
| `haproxy/certsync/crt-list.txt`                        | `/etc/haproxy/certsync/crt-list.txt`                     | haproxy     |
| `haproxy/certsync/allowlist.txt`                       | `/etc/haproxy/certsync/allowlist.txt`                     | haproxy     |
| `scripts/vault-acme-issue-all.sh`                      | `/usr/local/sbin/vault-acme-issue-all.sh`                | none        |
| `scripts/haproxy-certs-send`                           | `/usr/local/sbin/haproxy-certs-send`                     | none        |
| `scripts/haproxy-certs-recv`                           | `/usr/local/sbin/haproxy-certs-recv`                     | none        |
| `certbot/dns01/auth.sh`                               | `/usr/local/lib/certbot-dns01/auth.sh`                   | none        |
| `certbot/dns01/cleanup.sh`                             | `/usr/local/lib/certbot-dns01/cleanup.sh`                | none        |
| `certbot/hooks/deploy/50-haproxy-deploy`               | `/etc/letsencrypt/renewal-hooks/deploy/50-haproxy-deploy`| none        |
| `certbot/systemd/vault-acme-issue-all.timer`           | `/etc/systemd/system/vault-acme-issue-all.timer`         | systemd     |
| `certbot/systemd/vault-acme-issue-all.service`         | `/etc/systemd/system/vault-acme-issue-all.service`       | systemd     |
| `certbot/systemd/…/20-certsync.conf`                  | `/etc/systemd/system/…/20-certsync.conf`                 | systemd     |
| `keepalived/scripts/keepalived-notify-certsync.sh`     | `/usr/local/sbin/keepalived-notify-certsync.sh`          | none        |
| `keepalived/{HOSTNAME}-keepalived.conf`                | `/etc/keepalived/keepalived.conf`                        | keepalived  |
| `gitops/edge-gitops-sync.sh`                           | `/usr/local/sbin/edge-gitops-sync.sh`                    | gitops      |
| `gitops/edge-gitops-sync.service`                      | `/etc/systemd/system/edge-gitops-sync.service`           | systemd     |
| `gitops/edge-gitops-sync.timer`                        | `/etc/systemd/system/edge-gitops-sync.timer`             | systemd     |

**Initial bootstrap (one-time per node, as root):**

```bash
# 1. Clone with sparse checkout (only infrastructure/edge/)
git clone --depth 1 --filter=blob:none --sparse \
  git@github.com:necdetsanli/homelab.git /var/lib/edge-gitops/homelab
cd /var/lib/edge-gitops/homelab
git sparse-checkout set infrastructure/edge

# 2. Install the sync script + systemd units
cp infrastructure/edge/gitops/edge-gitops-sync.sh /usr/local/sbin/
chmod 0750 /usr/local/sbin/edge-gitops-sync.sh
cp infrastructure/edge/gitops/edge-gitops-sync.service /etc/systemd/system/
cp infrastructure/edge/gitops/edge-gitops-sync.timer /etc/systemd/system/

# 3. Enable and start
systemctl daemon-reload
systemctl enable --now edge-gitops-sync.timer

# 4. Run first sync immediately
systemctl start edge-gitops-sync.service
journalctl -u edge-gitops-sync.service --no-pager
```

After bootstrap, all future config changes pushed to `main` are auto-deployed
within 5 minutes.

**Manual trigger:**

```bash
sudo systemctl start edge-gitops-sync.service
journalctl -u edge-gitops-sync.service -n 30 --no-pager
```

**Verify current state:**

```bash
cat /var/lib/edge-gitops/last-deployed-commit    # deployed SHA
git -C /var/lib/edge-gitops/homelab rev-parse HEAD  # repo HEAD
systemctl list-timers edge-gitops-sync.timer      # next run
```

## TLS / PKI Pipeline

Edge TLS certificates are issued by **Vault PKI** (2-tier: Root RSA-4096 →
Intermediate RSA-4096) via the built-in **ACME** endpoint using **DNS-01**
challenges against **FreeIPA DNS**.

### Self-Provisioning Cert Orchestrator

`vault-acme-issue-all.sh` is the **single source of truth** for all edge
domains. Adding a domain to the `domains` array auto-provisions everything:

```
vault-acme-issue-all.timer (daily 03:17 UTC+3, ±1h jitter)
  → vault-acme-issue-all.service (flock protected, VIP owner only)
    → vault-acme-issue-all.sh
      Phase 0: kinit (Kerberos ticket for all DNS operations)
      Phase 1: ensure_cname() per domain
               └─ nsupdate -g → FreeIPA CNAME delegation (if missing)
      Phase 2: issue_and_deploy() per domain
               ├─ certbot DNS-01 via Vault ACME (role-scoped endpoint)
               │   ├─ auth.sh: nsupdate -g → TXT in acme.home.arpa
               │   ├─ Vault verifies DNS-01 → issues cert
               │   └─ cleanup.sh: deletes TXT record
               └─ assemble_pem() → /etc/haproxy/certs/<domain>.pem
      Phase 3: generate_haproxy_cert_config()
               ├─ crt-list.txt (SNI → PEM mapping, 20 entries)
               └─ allowlist.txt (PEM filenames for certsync, 21 entries)
      Phase 4: reload_haproxy()
               ├─ pre-flight: verify ALL PEMs in crt-list exist
               ├─ haproxy -c (config validation)
               └─ systemctl reload (or restart for new crt-list entries)
    → ExecStartPost: haproxy-certs-send
      └─ rsync PEMs + config → edge-2 via certsync SSH user
```

### Role-Scoped ACME Endpoints

Vault PKI roles enforce domain restrictions server-side:

| Role                  | ACME Endpoint                          | Domains                |
| --------------------- | -------------------------------------- | ---------------------- |
| `edge-mgmt-frontend`  | `pki_int/roles/edge-mgmt-frontend/acme` | `*.mgmt.home.arpa`   |
| `edge-app-frontend`   | `pki_int/roles/edge-app-frontend/acme`  | `*.app.home.arpa`    |
| `home-arpa-fqdns`     | `pki_int/roles/home-arpa-fqdns/acme`    | `*.home.arpa`        |

### CNAME Delegation Pattern

DNS-01 challenges never write to production zones. Each domain has a CNAME
delegation to the dedicated `acme.home.arpa` zone:

```
_acme-challenge.opnsense.mgmt.home.arpa  CNAME → opnsense.mgmt.home.arpa.acme.home.arpa.
```

CNAMEs are auto-provisioned by Phase 1 via `nsupdate -g` (GSS-TSIG with
Kerberos keytab `certbot-dnsupd/<hostname>@HOME.ARPA`). No shared secrets or
API tokens for DNS updates.

### Cert Sync (edge-1 → edge-2)

Certificates and config are synced from VIP owner to peer via `haproxy-certs-send`:

```
haproxy-certs-send (runs as ExecStartPost, or from gitops sync)
  ├─ VIP check (only runs on 192.168.20.22 holder)
  ├─ Allowlist validation (defence in depth)
  ├─ rsync certsync config (allowlist.txt + crt-list.txt) → edge-2
  └─ rsync PEMs (allowlisted only) → edge-2
      └─ SSH key: /home/certsync/.ssh/id_ed25519
         Edge-2 ForceCommand → haproxy-certs-recv
         (validates, enforces allowlist, fixes perms, reloads HAProxy)
```

Triggered by:
1. **Daily cert run** — `ExecStartPost` in `20-certsync.conf`
2. **Config change** — gitops sync detects HAProxy file changes + VIP owner
3. **VIP failover** — `keepalived-notify-certsync.sh` on MASTER transition

### PEM Assembly

certbot deploy hooks only fire on **renewal**, not initial issuance.
`vault-acme-issue-all.sh` handles both cases by calling `assemble_pem()` after
every `certbot certonly`, which idempotently builds `privkey.pem + fullchain.pem`
→ `/etc/haproxy/certs/<domain>.pem`.

### DNS Resolution Chain (Important for Troubleshooting)

```
Vault nodes → 127.0.0.53 (systemd-resolved) → AdGuard (192.168.20.53) → upstream
```

AdGuard must explicitly forward `acme.home.arpa` queries to FreeIPA
(`192.168.50.5`), otherwise Vault cannot verify DNS-01 challenges.

## HAProxy Architecture

### Frontend

- **`:80`** — HTTP to HTTPS redirect (301)
- **`:443`** — TLS termination with SNI-based cert selection via `crt-list.txt`
  - Default cert: `vault.home.arpa.pem` (loaded on bind line)
  - Per-service certs: loaded from `/etc/haproxy/certs/` via crt-list

### Backend Types

| Type              | TLS to Backend | CA Verification            | Examples                       |
| ----------------- | -------------- | -------------------------- | ------------------------------ |
| K8s Gateway API   | `ssl verify required` | `home-arpa-root-ca.crt` | Longhorn UI, Hubble UI         |
| Vault cluster     | `ssl verify required` | `home-arpa-root-ca.crt` | vault.home.arpa (active-node)  |
| ArgoCD            | `ssl verify none`     | —                        | argocd.mgmt.home.arpa          |
| Appliances        | `ssl verify none`     | —                        | OPNsense, Proxmox, iLO, etc.  |
| HTTP backends     | none                  | —                        | AdGuard, Maltrail, Netdata     |

K8s services route through **Cilium Gateway API** (Envoy) at `192.168.20.201:443`
with full TLS re-encryption and Vault PKI CA verification (cert-manager
`ClusterIssuer` using Vault K8s auth).

### Health Checks

All backends have `option httpchk` with appropriate health endpoints:
- Vault: `GET /v1/sys/health` (200 = active, 429 = standby → marked DOWN)
- ArgoCD: `GET /healthz` (200)
- Others: `GET /` (2xx/3xx)

## Keepalived

- **Unicast VRRP** — no multicast dependency
- **`preempt_delay 30`** — stable failback after recovery
- **Notify script** — `keepalived-notify-certsync.sh` triggers cert sync on
  MASTER transition so the new VIP owner has current certs

## Security

- **`auth_pass`** in keepalived is redacted in this repo. Replace the placeholder
  with your actual VRRP shared secret on the nodes.
- **`.mgmt.home.arpa`** backends are gated by source ACL — WireGuard only
  (`10.66.66.2/32`). Enforced by a catch-all rule: `is_mgmt_zone !from_wg_admin → 403`.
- **`vault.home.arpa`** API restricted to management VLAN (`192.168.50.0/24`),
  client VLAN (`192.168.20.0/24`), and K8s pod CIDR (`10.42.0.0/16`).
- **K8s Gateway backends** use `verify required` with the Vault PKI Root CA —
  full TLS re-encryption from HAProxy through Cilium Envoy to backend pods.
- **Appliance backends** currently use `verify none` (self-signed certs).
  Migrate to `verify required` with Vault PKI-issued certs over time.
- **certsync** uses a restricted SSH user with `ForceCommand` on edge-2 —
  only allowlisted PEM files can be written, validated on both sides.
