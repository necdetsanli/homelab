# Infrastructure as Code

This directory contains the full infrastructure definition for the homelab,
organized in layers that build on each other.

## Architecture Layers

```
Layer 3 │ ArgoCD        │ K8s apps, Helm charts, GitOps       │ clusters/
Layer 2 │ Ansible (OS)  │ VM/LXC post-provision configuration │ ansible/  (planned)
Layer 1 │ Terraform     │ VM & LXC provisioning on Proxmox    │ terraform/
Layer 0 │ Ansible (PVE) │ Proxmox host post-install config    │ ansible/
```

## Quick Start

### Layer 0 — Proxmox Host Configuration

```bash
cd ansible
ansible-playbook playbooks/proxmox-host.yml --check --diff   # dry-run
ansible-playbook playbooks/proxmox-host.yml                  # apply
```

This configures:

- APT repositories (no-subscription)
- Common packages
- Network interfaces (bridges, VLANs)
- NTP (chrony)
- SSH hardening
- Terraform API token + PVE role
- Cloud-init template images
- Backup schedule (vzdump)

### Layer 1 — VM & LXC Provisioning

```bash
cd terraform

# First time: copy and fill in secrets
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

terraform init
terraform plan
terraform apply
```

**Importing existing resources** (one-time):

```bash
# VMs
terraform import 'module.opnsense.proxmox_virtual_environment_vm.this' proxmox/qemu/100
terraform import 'module.wazuh.proxmox_virtual_environment_vm.this' proxmox/qemu/104
terraform import 'module.freeipa.proxmox_virtual_environment_vm.this' proxmox/qemu/106
terraform import 'module.k8s_master1.proxmox_virtual_environment_vm.this' proxmox/qemu/200
terraform import 'module.k8s_worker1.proxmox_virtual_environment_vm.this' proxmox/qemu/201
terraform import 'module.k8s_worker2.proxmox_virtual_environment_vm.this' proxmox/qemu/202
terraform import 'module.rancher.proxmox_virtual_environment_vm.this' proxmox/qemu/203
terraform import 'module.vault_1.proxmox_virtual_environment_vm.this' proxmox/qemu/206
terraform import 'module.vault_2.proxmox_virtual_environment_vm.this' proxmox/qemu/207
terraform import 'module.vault_3.proxmox_virtual_environment_vm.this' proxmox/qemu/208
terraform import 'module.truenas.proxmox_virtual_environment_vm.this' proxmox/qemu/300
terraform import 'module.nextcloud.proxmox_virtual_environment_vm.this' proxmox/qemu/301

# LXCs
terraform import 'module.unifi.proxmox_virtual_environment_container.this' proxmox/lxc/101
terraform import 'module.adguard.proxmox_virtual_environment_container.this' proxmox/lxc/102
terraform import 'module.edge_1.proxmox_virtual_environment_container.this' proxmox/lxc/204
terraform import 'module.edge_2.proxmox_virtual_environment_container.this' proxmox/lxc/205
terraform import 'module.meshtastic.proxmox_virtual_environment_container.this' proxmox/lxc/210
```

## Inventory

| ID  | Name           | Type | Cores | RAM   | Disk | VLAN | Role                        |
| --- | -------------- | ---- | ----- | ----- | ---- | ---- | --------------------------- |
| 100 | opnsense       | VM   | 8     | 12 GB | 32G  | —    | Firewall / router           |
| 101 | UNIFI-CTRL01   | LXC  | 2     | 2 GB  | 16G  | 20   | UniFi controller            |
| 102 | ADGUARD        | LXC  | 2     | 1 GB  | 8G   | 20   | DNS filtering               |
| 104 | Wazuh          | VM   | 2     | 8 GB  | 64G  | 50   | SIEM                        |
| 106 | ipa            | VM   | 2     | 4 GB  | 32G  | 50   | FreeIPA (DNS/Kerberos/LDAP) |
| 200 | k8s-master1    | VM   | 4     | 8 GB  | 60G  | 20   | RKE2 control-plane          |
| 201 | k8s-worker-1   | VM   | 8     | 24 GB | 120G | 20   | RKE2 worker                 |
| 202 | k8s-worker-2   | VM   | 8     | 24 GB | 120G | 20   | RKE2 worker                 |
| 203 | rancher        | VM   | 2     | 8 GB  | 32G  | 20   | Rancher management          |
| 204 | edge-1         | LXC  | 1     | 1 GB  | 8G   | 20   | HAProxy ingress             |
| 205 | edge-2         | LXC  | 1     | 1 GB  | 8G   | 20   | HAProxy ingress             |
| 206 | vault-1        | VM   | 2     | 2 GB  | 32G  | 20   | Vault HA (leader)           |
| 207 | vault-2        | VM   | 2     | 2 GB  | 32G  | 20   | Vault HA (follower)         |
| 208 | vault-3        | VM   | 2     | 2 GB  | 32G  | 20   | Vault HA (follower)         |
| 210 | meshtastic-web | LXC  | 2     | 1 GB  | 8G   | 20   | Meshtastic T-Beam gateway   |
| 300 | TrueNAS-Scale  | VM   | 2     | 8 GB  | 32G  | 20   | NAS (HBA passthrough)       |
| 301 | NextCloud      | VM   | 2     | 8 GB  | 64G  | 20   | File sync                   |

**Total**: 12 VMs + 5 LXCs = 17 guests on single Proxmox node

## Network Topology

```
Internet ──► OPNsense (.50.1) ──► vmbr0 (VLAN trunk)
                                    ├── VLAN 20 (servers)  192.168.20.0/24
                                    └── VLAN 50 (mgmt)     192.168.50.0/24
              vmbr1 ◄── OPNsense secondary NIC
```

## Planned

- **MinIO LXC** (CTID 211) — S3 for Terraform remote state, Velero, Loki, Mimir
- **Layer 2 Ansible roles** — OS hardening, RKE2 bootstrap, Vault setup, edge config
