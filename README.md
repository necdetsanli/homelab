# Homelab

This repository documents my personal homelab infrastructure and GitOps journey.
It is intentionally **public-safe**: no secrets, private keys, kubeconfigs, or internal-only configuration is committed.

## Hardware

- **Server:** HP Proliant DL380 G9
- **Switch:** Cisco WS-C3560CX-12-TC-S
- **Access Point:** UniFi AP AC-30 Lite

## Core Platform

- **Virtualization:** Proxmox
- **Firewall / Router:** OPNsense
- **Kubernetes:** RKE2 (managed via Rancher)
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

## Security & Observability

- **SIEM:** Wazuh

## High Availability

- **Reverse Proxy:** HAProxy + Keepalived (failover / high availability)
- **Vault PKI:** 3-node HA + failover (separate VM)

## Diagrams

All architecture diagrams live under `diagrams/`.

> Note: A Draw.io diagram will be added first, but it is currently **outdated** and will be updated as the architecture evolves.
