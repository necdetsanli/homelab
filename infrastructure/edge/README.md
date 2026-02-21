# Edge Reverse-Proxy Tier

Two Ubuntu VMs running **HAProxy + Keepalived** in active/passive with a
floating VIP. No services are exposed to the internet — all access is
restricted to specific hosts on specific VLANs (management, client, WireGuard).

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
                │
                ▼
   Backend services (OPNsense, Vault, Proxmox, K8s Ingress, …)
```

## Components

| Component  | Version  | Purpose                                            |
| ---------- | -------- | -------------------------------------------------- |
| HAProxy    | 2.8+ LTS | TLS termination, host-based routing, health checks |
| Keepalived | 2.x      | VRRP failover, VIP management                      |

## DNS Zones

| Zone               | Access         | Examples                                            |
| ------------------ | -------------- | --------------------------------------------------- |
| `*.app.home.arpa`  | All VLANs      | `nextcloud.app.home.arpa`                           |
| `*.mgmt.home.arpa` | WireGuard only | `opnsense.mgmt.home.arpa`, `rancher.mgmt.home.arpa` |
| `vault.home.arpa`  | Internal VLANs | Vault API (active-node routing)                     |

## File Layout

```
infrastructure/edge/
├── README.md
├── haproxy/
│   ├── haproxy.cfg              # Shared config (identical on both nodes)
│   └── certsync/
│       ├── crt-list.txt         # HAProxy SNI → cert mapping
│       └── allowlist.txt        # PEM filenames allowed for rsync to edge-2
├── keepalived/
│   ├── edge-1-keepalived.conf   # MASTER  priority 120
│   ├── edge-2-keepalived.conf   # BACKUP  priority 110
│   └── scripts/
│       └── keepalived-notify-certsync.sh   # VIP transition trigger
├── certbot/
│   ├── dns01/
│   │   ├── auth.sh              # DNS-01 auth hook (FreeIPA nsupdate / GSS-TSIG)
│   │   └── cleanup.sh           # DNS-01 cleanup hook (delete TXT record)
│   ├── hooks/
│   │   └── deploy/
│   │       └── 50-haproxy-deploy  # Assemble PEM bundle + reload HAProxy
│   └── systemd/
│       ├── vault-acme-issue-all.timer       # Daily renewal timer
│       ├── vault-acme-issue-all.service     # One-shot certbot orchestrator
│       └── vault-acme-issue-all.service.d/
│           └── 20-certsync.conf             # Drop-in: rsync to edge-2
└── scripts/
    ├── vault-acme-issue-all.sh  # Main orchestrator (certbot per domain)
    └── haproxy-certs-send       # rsync PEMs to edge-2 via certsync user
```

## Deployment Notes

- Configs are deployed via `scp` or Ansible (not managed by ArgoCD).
- HAProxy loads all PEM certs from `/etc/haproxy/certs/` and a `crt-list.txt`
  synced by a Keepalived notify script (`keepalived-notify-certsync.sh`).
- Keepalived uses unicast VRRP (no multicast dependency) with `preempt_delay 30`
  for stable failback.
- The `check_haproxy.sh` health script should return 0 when HAProxy is healthy,
  non-zero otherwise (e.g., `killall -0 haproxy`).

## TLS / PKI Pipeline

Edge TLS certificates are issued by **Vault PKI** (intermediate CA) via the
built-in **ACME** endpoint using **DNS-01** challenges against **FreeIPA DNS**.

```
vault-acme-issue-all.timer (daily 03:17 + jitter)
  → vault-acme-issue-all.sh   (loops all domains, calls certbot)
    → certbot --server vault ACME --manual-auth-hook auth.sh
      → auth.sh: kinit + nsupdate -g → TXT in acme.home.arpa zone
      → Vault verifies DNS-01 → issues cert
      → cleanup.sh: deletes TXT record
      → 50-haproxy-deploy: cat key+chain → PEM, validate, reload
    → haproxy-certs-send (ExecStartPost): rsync PEMs → edge-2
```

**CNAME delegation pattern** (no writes to production DNS zone):

```
_acme-challenge.opnsense.mgmt.home.arpa  CNAME → opnsense.mgmt.home.arpa.acme.home.arpa.
```

Authentication: Kerberos keytab (`certbot-dnsupd/edge-1.home.arpa@HOME.ARPA`)
for GSS-TSIG `nsupdate`. No shared secrets or API tokens for DNS updates.

## Security

- **`auth_pass`** in keepalived is redacted in this repo. Replace the placeholder
  with your actual VRRP shared secret on the nodes.
- `.mgmt.home.arpa` backends are gated by source ACL (WireGuard only:
  `10.66.66.2/32`).
- `vault.home.arpa` API restricted to management and client VLANs.
- Backend TLS verification is `verify none` for appliances with self-signed certs;
  migrate to `verify required` with Vault PKI-issued certs over time.
