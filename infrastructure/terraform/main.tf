# ──────────────────────────────────────────────────────────────
# Homelab Infrastructure — VM & LXC Definitions
# ──────────────────────────────────────────────────────────────
# This file declares ALL existing VMs and LXC containers.
# To import existing resources into state:
#
#   terraform import 'module.opnsense.proxmox_virtual_environment_vm.this' proxmox/qemu/100
#   terraform import 'module.wazuh.proxmox_virtual_environment_vm.this' proxmox/qemu/104
#   ... etc
#
# For LXCs:
#   terraform import 'module.unifi.proxmox_virtual_environment_container.this' proxmox/lxc/101
#   ... etc
# ──────────────────────────────────────────────────────────────

locals {
  node = var.proxmox_node
}

# ╔════════════════════════════════════════════════════════════╗
# ║  VIRTUAL MACHINES                                         ║
# ╚════════════════════════════════════════════════════════════╝

# ── 100 — OPNsense (firewall/router) ────────────────────────
module "opnsense" {
  source = "./modules/vm"

  node_name = local.node
  vmid      = 100
  name      = "opnsense"
  tags      = ["infra", "mgmt", "sec"]

  cores  = 8
  memory = 12288

  disk_size    = 32
  disk_ssd     = false
  disk_discard = false

  os_type  = "other"
  vga_type = "std"

  # OPNsense: untagged on vmbr0 (it does its own VLAN trunking)
  network_bridge   = var.default_bridge
  network_vlan     = null
  network_firewall = false

  # Second NIC — WAN / secondary uplink
  additional_nics = [
    {
      bridge = "vmbr1"
    }
  ]

  startup_order = 1

  description = "OPNsense firewall/router — gateway for all VLANs"
}

# ── 104 — Wazuh (SIEM) ──────────────────────────────────────
module "wazuh" {
  source = "./modules/vm"

  node_name = local.node
  vmid      = 104
  name      = "Wazuh"
  tags      = ["mgmt", "sec"]

  cores  = 2
  memory = 8192

  disk_size = 64

  network_bridge = var.default_bridge
  network_vlan   = var.mgmt_vlan_id

  description = "Wazuh SIEM — security monitoring and log analysis"
}

# ── 106 — FreeIPA (identity management) ─────────────────────
module "freeipa" {
  source = "./modules/vm"

  node_name = local.node
  vmid      = 106
  name      = "ipa"
  tags      = ["infra", "mgmt", "sec"]

  cores  = 2
  memory = 4096

  disk_size = 32

  network_bridge   = var.default_bridge
  network_vlan     = var.mgmt_vlan_id
  network_firewall = true

  vga_type = "qxl"

  startup_order = 2

  description = "FreeIPA — DNS, Kerberos, LDAP, PKI for home.arpa"
}

# ── 200 — k8s-master1 (RKE2 control plane) ──────────────────
module "k8s_master1" {
  source = "./modules/vm"

  node_name = local.node
  vmid      = 200
  name      = "k8s-master1"
  tags      = ["apps", "k8s"]

  cores  = 4
  memory = 8192

  disk_size = 60

  network_bridge = var.default_bridge
  network_vlan   = var.server_vlan_id

  description = "RKE2 control-plane node (etcd + control-plane)"
}

# ── 201 — k8s-worker-1 ──────────────────────────────────────
module "k8s_worker1" {
  source = "./modules/vm"

  node_name = local.node
  vmid      = 201
  name      = "k8s-worker-1"
  tags      = ["apps", "k8s"]

  cores  = 8
  memory = 24576

  disk_size = 120

  network_bridge   = var.default_bridge
  network_vlan     = var.server_vlan_id
  network_firewall = true

  description = "RKE2 worker node 1 — primary workload runner"
}

# ── 202 — k8s-worker-2 ──────────────────────────────────────
module "k8s_worker2" {
  source = "./modules/vm"

  node_name = local.node
  vmid      = 202
  name      = "k8s-worker-2"
  tags      = ["apps", "k8s"]

  cores  = 8
  memory = 24576

  disk_size = 120

  network_bridge = var.default_bridge
  network_vlan   = var.server_vlan_id

  description = "RKE2 worker node 2 — primary workload runner"
}

# ── 203 — Rancher ────────────────────────────────────────────
module "rancher" {
  source = "./modules/vm"

  node_name = local.node
  vmid      = 203
  name      = "rancher"
  tags      = ["infra", "k8s"]

  cores  = 2
  memory = 8192

  disk_size = 32

  network_bridge = var.default_bridge
  network_vlan   = var.server_vlan_id

  description = "Rancher server — RKE2 cluster lifecycle management"
}

# ── 206–208 — Vault HA cluster ───────────────────────────────
module "vault_1" {
  source = "./modules/vm"

  node_name = local.node
  vmid      = 206
  name      = "vault-1"
  tags      = ["infra", "pki"]

  cores  = 2
  memory = 2048

  disk_size = 32

  network_bridge   = var.default_bridge
  network_vlan     = var.server_vlan_id
  network_firewall = true

  description = "HashiCorp Vault node 1 — HA Raft cluster leader"
}

module "vault_2" {
  source = "./modules/vm"

  node_name = local.node
  vmid      = 207
  name      = "vault-2"
  tags      = ["infra", "pki"]

  cores  = 2
  memory = 2048

  disk_size = 32

  network_bridge = var.default_bridge
  network_vlan   = var.server_vlan_id

  description = "HashiCorp Vault node 2 — HA Raft cluster follower"
}

module "vault_3" {
  source = "./modules/vm"

  node_name = local.node
  vmid      = 208
  name      = "vault-3"
  tags      = ["infra", "pki"]

  cores  = 2
  memory = 2048

  disk_size = 32

  network_bridge   = var.default_bridge
  network_vlan     = var.server_vlan_id
  network_firewall = true

  description = "HashiCorp Vault node 3 — HA Raft cluster follower"
}

# ── 300 — TrueNAS Scale (NAS + HBA passthrough) ─────────────
module "truenas" {
  source = "./modules/vm"

  node_name = local.node
  vmid      = 300
  name      = "TrueNAS-Scale"
  tags      = ["apps", "infra"]

  cores    = 2
  memory   = 8192
  cpu_type = "x86-64-v2-AES"
  bios     = "ovmf"

  disk_size = 32

  network_bridge = var.default_bridge
  network_vlan   = var.server_vlan_id

  # HBA controller passthrough (LSI / Dell PERC)
  pci_devices = [
    {
      device = "0000:03:00"
      id     = "0"
      pcie   = true
    }
  ]

  description = "TrueNAS Scale — NFS/iSCSI/SMB storage with HBA passthrough"
}

# ── 301 — NextCloud ──────────────────────────────────────────
module "nextcloud" {
  source = "./modules/vm"

  node_name = local.node
  vmid      = 301
  name      = "NextCloud"
  tags      = ["apps"]

  cores    = 2
  memory   = 8192
  cpu_type = "x86-64-v2-AES"

  disk_size = 64

  network_bridge   = var.default_bridge
  network_vlan     = var.server_vlan_id
  network_firewall = true

  description = "Nextcloud — self-hosted file sync and collaboration"
}


# ╔════════════════════════════════════════════════════════════╗
# ║  LXC CONTAINERS                                           ║
# ╚════════════════════════════════════════════════════════════╝

# ── 101 — UniFi Controller ──────────────────────────────────
module "unifi" {
  source = "./modules/lxc"

  node_name = local.node
  ctid      = 101
  hostname  = "UNIFI-CTRL01"
  tags      = ["infra", "mgmt"]

  cores  = 2
  memory = 2048
  swap   = 512

  disk_size = 16

  os_template = "local:vztmpl/alpine-3.21-default_20250108_amd64.tar.xz"
  os_type     = "alpine"

  network_bridge   = var.default_bridge
  network_vlan     = var.server_vlan_id
  network_firewall = true
  network_dhcp     = true

  description = "UniFi Network Controller — AP and switch management"
}

# ── 102 — AdGuard Home ──────────────────────────────────────
module "adguard" {
  source = "./modules/lxc"

  node_name = local.node
  ctid      = 102
  hostname  = "ADGUARD"
  tags      = ["infra"]

  cores  = 2
  memory = 1024
  swap   = 0

  disk_size = 8

  os_template = "local:vztmpl/alpine-3.21-default_20250108_amd64.tar.xz"
  os_type     = "alpine"

  network_bridge = var.default_bridge
  network_vlan   = var.server_vlan_id
  network_dhcp   = true

  dns_servers = ["192.168.20.1"]

  description = "AdGuard Home — DNS filtering and ad blocking"
}

# ── 204 — edge-1 (HAProxy ingress) ──────────────────────────
module "edge_1" {
  source = "./modules/lxc"

  node_name = local.node
  ctid      = 204
  hostname  = "edge-1"
  tags      = ["haproxy", "infra"]

  cores  = 1
  memory = 1024
  swap   = 0

  disk_size = 8

  os_template = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  os_type     = "ubuntu"

  network_bridge = var.default_bridge
  network_vlan   = var.server_vlan_id
  network_dhcp   = true

  # NOTE: onboot was MISSING in current config — fixed here
  on_boot = true

  description = "Edge node 1 — HAProxy + Keepalived (VIP ingress)"
}

# ── 205 — edge-2 (HAProxy ingress) ──────────────────────────
module "edge_2" {
  source = "./modules/lxc"

  node_name = local.node
  ctid      = 205
  hostname  = "edge-2"
  tags      = ["haproxy", "infra"]

  cores  = 1
  memory = 1024
  swap   = 0

  disk_size = 8

  os_template = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  os_type     = "ubuntu"

  network_bridge = var.default_bridge
  network_vlan   = var.server_vlan_id
  network_dhcp   = true

  on_boot = true

  description = "Edge node 2 — HAProxy + Keepalived (VIP ingress)"
}

# ── 210 — Meshtastic Web Gateway ────────────────────────────
module "meshtastic" {
  source = "./modules/lxc"

  node_name = local.node
  ctid      = 210
  hostname  = "meshtastic-web"
  tags      = ["apps", "iot"]

  cores  = 2
  memory = 1024
  swap   = 0

  disk_size = 8

  os_template = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  os_type     = "ubuntu"

  network_bridge = var.default_bridge
  network_vlan   = var.server_vlan_id
  network_dhcp   = true

  # NOTE: onboot was MISSING in current config — fixed here
  on_boot = true

  # USB passthrough for T-Beam device (/dev/ttyACM0)
  # Requires manual lxc.mount.entry in /etc/pve/lxc/210.conf
  # (Terraform provider does not support raw lxc config)

  description = "Meshtastic web gateway — T-Beam USB serial bridge"
}

# ── 212 — Ansible Control Node ───────────────────────────
module "ansible_ctrl" {
  source = "./modules/lxc"

  node_name = local.node
  ctid      = 212
  hostname  = "ansible"
  tags      = ["infra", "mgmt"]

  cores  = 1
  memory = 1024
  swap   = 0

  disk_size = 8

  os_template = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  os_type     = "ubuntu"

  network_bridge  = var.default_bridge
  network_vlan    = var.server_vlan_id
  network_dhcp    = false
  network_ip      = "192.168.20.80/24"
  network_gateway = "192.168.20.1"

  dns_servers = ["192.168.50.5", "192.168.20.53"]

  on_boot = true

  description = "Ansible control node — FreeIPA-enrolled, runs playbooks"
}

# ── Planned: MinIO (S3 for Terraform state / Velero / Loki) ─
# Uncomment after deciding on CTID and deploying OS template.
#
# module "minio" {
#   source = "./modules/lxc"
#
#   node_name = local.node
#   ctid      = 211
#   hostname  = "minio"
#   tags      = ["infra"]
#
#   cores  = 1
#   memory = 1024
#   swap   = 0
#
#   disk_size = 16
#
#   os_template = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
#   os_type     = "ubuntu"
#
#   network_bridge = var.default_bridge
#   network_vlan   = var.server_vlan_id
#   network_dhcp   = false
#   network_ip     = "192.168.20.55/24"
#   network_gateway = "192.168.20.1"
#
#   dns_servers = ["192.168.20.11", "192.168.50.10"]
#
#   on_boot = true
#
#   description = "MinIO S3 — Terraform state, Velero backups, Loki/Mimir storage"
# }
