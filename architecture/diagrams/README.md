# Architecture Diagrams

Enterprise-grade Draw.io diagrams documenting the homelab platform architecture. Open any `.drawio` file in [draw.io](https://app.diagrams.net/) or the VS Code Draw.io extension.

| #   | Diagram                                                                                   | Description                                                              |
| --- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| 01  | [Physical & Network Topology](01-physical-network-topology.drawio)                        | HP DL380 G9, Cisco switch ports, ZTE ONT, OPNsense VLANs, all VMs/LXCs   |
| 02  | [Proxmox VM & LXC Overview](02-proxmox-vm-lxc-overview.drawio)                            | Functional tiers, resource allocation, VLAN mapping, storage layout      |
| 03  | [GitOps — ArgoCD App of Apps](03-gitops-argocd-app-of-apps.drawio)                        | Bootstrap flow, sync waves -2 to 2, 10 child apps, Helm + Git sources    |
| 04  | [Ingress Traffic Flow & TLS](04-ingress-tls-flow.drawio)                                  | HAProxy HA → Gateway API → backend, full TLS re-encryption chain         |
| 05  | [Security — WireGuard + SPIRE + Zero Trust](05-security-wireguard-spire-zerotrust.drawio) | 3-layer model: kernel encryption, SPIFFE identity, default-deny policies |
| 06  | [Cilium eBPF Networking](06-cilium-ebpf-networking.drawio)                                | Native routing, LB-IPAM, L2/BGP, Gateway API, Hubble observability       |
| 07  | [PKI, Secrets & Certificates](07-pki-secrets-certificates.drawio)                         | Vault PKI hierarchy, cert-manager ACME, edge certbot pipeline, VSO       |
| 08  | [Storage — Longhorn + NFS](08-storage-longhorn-nfs.drawio)                                | NVMe local, TrueNAS ZFS pools, Longhorn distributed block, NFS exports   |
