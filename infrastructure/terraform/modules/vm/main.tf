# ──────────────────────────────────────────────────────────────
# Proxmox VM Module — Reusable virtual machine resource
# ──────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "this" {
  node_name = var.node_name
  vm_id     = var.vmid
  name      = var.name
  tags      = var.tags

  description = var.description

  on_boot  = var.on_boot
  started  = var.started
  machine  = var.machine
  bios     = var.bios

  # Boot order
  boot_order = var.boot_order

  # Startup/shutdown behaviour
  dynamic "startup" {
    for_each = var.startup_order != null ? [1] : []
    content {
      order      = var.startup_order
      up_delay   = var.startup_up_delay
      down_delay = var.startup_down_delay
    }
  }

  cpu {
    type    = var.cpu_type
    cores   = var.cores
    sockets = var.sockets
  }

  memory {
    dedicated = var.memory
  }

  agent {
    enabled = var.agent_enabled
  }

  # Primary disk
  disk {
    datastore_id = var.storage
    size          = var.disk_size
    interface     = "scsi0"
    iothread      = true
    ssd           = var.disk_ssd
    discard       = var.disk_discard ? "on" : "ignore"
    file_format   = "raw"
  }

  # Additional disks
  dynamic "disk" {
    for_each = var.additional_disks
    content {
      datastore_id = disk.value.storage
      size          = disk.value.size
      interface     = disk.value.interface
      iothread      = true
      ssd           = lookup(disk.value, "ssd", true)
      discard       = lookup(disk.value, "discard", true) ? "on" : "ignore"
      file_format   = "raw"
    }
  }

  # EFI disk (UEFI boot)
  dynamic "efi_disk" {
    for_each = var.bios == "ovmf" ? [1] : []
    content {
      datastore_id = var.storage
      type         = "4m"
    }
  }

  scsi_hardware = "virtio-scsi-single"

  # Primary NIC
  network_device {
    bridge  = var.network_bridge
    vlan_id = var.network_vlan
    model   = "virtio"
    firewall = var.network_firewall
  }

  # Additional NICs
  dynamic "network_device" {
    for_each = var.additional_nics
    content {
      bridge   = network_device.value.bridge
      vlan_id  = lookup(network_device.value, "vlan_id", null)
      model    = "virtio"
      firewall = lookup(network_device.value, "firewall", false)
    }
  }

  # PCI passthrough
  dynamic "hostpci" {
    for_each = var.pci_devices
    content {
      device = hostpci.value.device
      id     = hostpci.value.id
      pcie   = lookup(hostpci.value, "pcie", false)
      rombar = lookup(hostpci.value, "rombar", true)
    }
  }

  # Cloud-init (only when template_vmid is set, i.e., cloned VMs)
  dynamic "initialization" {
    for_each = var.cloud_init_enabled ? [1] : []
    content {
      datastore_id = var.storage

      ip_config {
        ipv4 {
          address = var.cloud_init_ip
          gateway = var.cloud_init_gateway
        }
      }

      dns {
        servers = var.cloud_init_dns
        domain  = var.cloud_init_domain
      }

      user_account {
        username = var.cloud_init_user
        keys     = var.cloud_init_ssh_keys
      }
    }
  }

  operating_system {
    type = var.os_type
  }

  # VGA
  vga {
    type = var.vga_type
  }

  # Serial console (for cloud-init / headless)
  dynamic "serial_device" {
    for_each = var.serial_enabled ? [1] : []
    content {
      device = "socket"
    }
  }

  lifecycle {
    ignore_changes = [
      # Ignore cloud-init changes after initial provision
      initialization,
      # Ignore disk size changes from manual resizing
      disk[0].size,
    ]
  }
}
