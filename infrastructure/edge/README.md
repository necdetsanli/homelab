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
│   └── haproxy.cfg              # Shared config (identical on both nodes)
└── keepalived/
    ├── edge-1-keepalived.conf   # MASTER  priority 120
    └── edge-2-keepalived.conf   # BACKUP  priority 110
```

## Deployment Notes

- Configs are deployed via `scp` or Ansible (not managed by ArgoCD).
- HAProxy loads all PEM certs from `/etc/haproxy/certs/` and a `crt-list.txt`
  synced by a Keepalived notify script (`keepalived-notify-certsync.sh`).
- Keepalived uses unicast VRRP (no multicast dependency) with `preempt_delay 30`
  for stable failback.
- The `check_haproxy.sh` health script should return 0 when HAProxy is healthy,
  non-zero otherwise (e.g., `killall -0 haproxy`).

## Security

- **`auth_pass`** in keepalived is redacted in this repo. Replace the placeholder
  with your actual VRRP shared secret on the nodes.
- `.mgmt.home.arpa` backends are gated by source ACL (WireGuard only:
  `10.66.66.2/32`).
- `vault.home.arpa` API restricted to management and client VLANs.
- Backend TLS verification is `verify none` for appliances with self-signed certs;
  migrate to `verify required` with Vault PKI-issued certs over time.
