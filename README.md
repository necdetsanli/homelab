# Homelab

This repository documents my personal homelab infrastructure and GitOps journey.
It is intentionally **public-safe**: no secrets, private keys, kubeconfigs, or internal-only configuration is committed.

## Hardware

- **Server:** HP Proliant DL380 G9
- **Switch:** Cisco WS-C3560CX-12-TC-S
- **Access Point:** Ubiquiti UniFi AC Lite

## Core Platform

- **Virtualization:** Proxmox
- **Firewall / Router:** OPNsense
- **Kubernetes:** RKE2 (managed via Rancher, cis compliant)
- **GitOps:** Argo CD

## DNS & Identity

- **DNS:** AdGuard Home
  - Upstream: Unbound
  - Internal zones / identity integration: FreeIPA
    - `home.arpa`
    - `mgmt.home.arpa`
    - `app.home.arpa`
- **User & Access Management:** FreeIPA (SSO / centralized authN/authZ)

## Storage & Cloud

- **NAS:** TrueNAS
- **Cloud (Self-hosted):** Nextcloud

## Kubernetes Networking & Security

### Cilium (eBPF-based CNI)

Full kube-proxy replacement with native eBPF datapath:

- **Routing:** Native routing, `bpf.masquerade`, `bpf.tproxy`, BBR congestion control
- **Load Balancing:** LB-IPAM (pool `192.168.20.200–250`), L2 announcements, BGP (AS 64501 ↔ OPNsense AS 64500)
- **Gateway API:** v1.4.1 Experimental channel with embedded Envoy proxy

### Encryption & Mutual Authentication (Phase 2)

**WireGuard transparent encryption** — all pod-to-pod traffic between nodes is encrypted at the kernel level. Control-plane node is opted out by default (host-network traffic already TLS-protected by Kubernetes).

**SPIRE mutual authentication** — every workload receives a SPIFFE SVID (X.509 identity) from a dedicated SPIRE infrastructure (trust domain: `spire.cilium`):

| Component | Scope | Details |
|-----------|-------|---------|
| SPIRE Server | 1 replica, StatefulSet | Longhorn 1Gi PV, `cilium-spire` namespace |
| SPIRE Agent | DaemonSet (all 3 nodes) | Full tolerations including `etcd:NoExecute` |
| Cilium Auth | `authentication.enabled: true` | Chart defaults to `false` — must be explicit |

Enforcement via `authentication.mode: required` on `CiliumNetworkPolicy` ingress rules:

| Policy | Source → Destination |
|--------|---------------------|
| `allow-hubble-relay` | hubble-ui → hubble-relay (port 4245) |
| `allow-spire-agent-to-server` | spire-agent → spire-server (port 8081) |
| `allow-longhorn-internal` | longhorn intra-namespace (all pods) |

> Policies using `fromEntities` (CoreDNS, metrics-server, webhooks, gateway ingress) are **not eligible** — reserved identities don't carry SPIFFE SVIDs.

### TLS Re-encryption (Phase 1)

End-to-end encrypted path from client to pod:

```
Client ──TLS──▶ HAProxy (edge VIP) ──TLS──▶ Gateway/Envoy ──plaintext──▶ Pod
```

- **Edge:** HAProxy 2.8 LTS behind Keepalived VIP (`192.168.20.22`), terminates and re-encrypts to cluster
- **Certificates:** Vault PKI (Root RSA-4096 10yr → Intermediate 5yr) via cert-manager `ClusterIssuer`
- **Gateway:** HTTPS listener on `:443` with TLS Terminate mode

### Network Policies

Zero-trust model — every namespace starts with `default-deny-ingress`, then explicit `CiliumNetworkPolicy` allow rules per service:

- `allow-coredns` — DNS from all cluster sources (port 53)
- `allow-hubble-relay` — hubble-ui only (mutual auth enforced)
- `allow-metrics-server` — kube-apiserver only
- `allow-gateway-to-*` — Envoy ingress identity to backend services
- `allow-apiserver-webhook` — webhook ports for cert-manager, Longhorn
- `allow-spire-agent-to-server` — gRPC registration (mutual auth enforced)
- `allow-longhorn-internal` — intra-namespace (mutual auth enforced)

## Security & Observability

- **SIEM:** Wazuh
- **Flow Observability:** Hubble (UI exposed via Gateway API + TLS)

## High Availability

- **Reverse Proxy:** HAProxy + Keepalived (failover / high availability)
- **Vault PKI:** 3-node HA + failover

## Diagrams

All architecture diagrams live under `diagrams/`.

> Note: A Draw.io diagram will be added first, but it is currently **outdated** and will be updated as the architecture evolves.
