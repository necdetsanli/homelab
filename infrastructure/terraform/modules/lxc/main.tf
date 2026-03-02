# ──────────────────────────────────────────────────────────────
# Proxmox LXC Module — Reusable container resource
# ──────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_container" "this" {
  node_name = var.node_name
  vm_id     = var.ctid
  tags      = var.tags

  description = var.description

  started  = var.started
  start_on_boot = var.on_boot

  dynamic "startup" {
    for_each = var.startup_order != null ? [1] : []
    content {
      order      = var.startup_order
      up_delay   = var.startup_up_delay
      down_delay = var.startup_down_delay
    }
  }

  unprivileged = var.unprivileged

  features {
    nesting = var.nesting
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  # Root filesystem
  disk {
    datastore_id = var.storage
    size          = var.disk_size
  }

  # OS template
  operating_system {
    template_file_id = var.os_template
    type             = var.os_type
  }

  # Primary NIC
  network_interface {
    name     = "eth0"
    bridge   = var.network_bridge
    vlan_id  = var.network_vlan
    firewall = var.network_firewall

    dynamic "ipv4" {
      for_each = var.network_dhcp ? [] : [1]
      content {
        address = var.network_ip
        gateway = var.network_gateway
      }
    }

    dynamic "ipv4" {
      for_each = var.network_dhcp ? [1] : []
      content {
        address = "dhcp"
      }
    }
  }

  # DNS
  dynamic "dns" {
    for_each = length(var.dns_servers) > 0 ? [1] : []
    content {
      domain  = var.dns_domain
      servers = var.dns_servers
    }
  }

  # Cloud-init / initial config
  initialization {
    hostname = var.hostname
  }

  # Mount points (USB passthrough, bind mounts, etc.)
  dynamic "mount_point" {
    for_each = var.mount_points
    content {
      volume = mount_point.value.volume
      path   = mount_point.value.path
      shared = lookup(mount_point.value, "shared", false)
    }
  }

  lifecycle {
    ignore_changes = [
      # Ignore template changes after creation
      operating_system,
      # Ignore disk resizes done manually
      disk[0].size,
    ]
  }
}
