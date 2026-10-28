resource "libvirt_network" "red_nat" {
  name      = "iac-nat"
  mode      = "nat"
  addresses = [var.red_nat_cidr]
  autostart = true

  dhcp {
    enabled = true
  }
}

resource "libvirt_network" "red_datos" {
  name      = "iac-datos"
  mode      = "none"
  autostart = true
}

locals {
  mac_web_nat   = "52:54:00:10:00:0a"
  mac_web_datos = "52:54:00:20:00:0a"
  mac_bd_nat    = "52:54:00:10:00:14"
  mac_bd_datos  = "52:54:00:20:00:14"
  ssh_key       = trimspace(file(pathexpand(var.ssh_public_key)))
}

# Servidor web (Debian 13)
resource "libvirt_volume" "web_disk" {
  name             = "iac-web.qcow2"
  pool             = var.libvirt_pool_name
  base_volume_name = var.imagen_web
  base_volume_pool = var.libvirt_pool_name
  format           = "qcow2"
}

resource "libvirt_cloudinit_disk" "web_cloudinit" {
  name = "iac-web-cloudinit.iso"
  pool = var.libvirt_pool_name
  user_data = templatefile("${path.module}/cloud-init/user-data.yaml.tftpl", {
    hostname = "web"
    usuario  = var.usuario
    ssh_key  = local.ssh_key
  })
  network_config = templatefile("${path.module}/cloud-init/network-config.yaml.tftpl", {
    mac_nat   = local.mac_web_nat
    mac_datos = local.mac_web_datos
    ip_datos  = var.ip_datos_web
  })
}

resource "libvirt_domain" "web" {
  name      = "iac-web"
  memory    = var.memoria_web
  vcpu      = 1
  cloudinit = libvirt_cloudinit_disk.web_cloudinit.id

  cpu {
    mode = "host-passthrough"
  }

  network_interface {
    network_id     = libvirt_network.red_nat.id
    mac            = local.mac_web_nat
    wait_for_lease = true
  }

  network_interface {
    network_id = libvirt_network.red_datos.id
    mac        = local.mac_web_datos
  }

  disk {
    volume_id = libvirt_volume.web_disk.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}

# Servidor de base de datos (Ubuntu 26.04)
resource "libvirt_volume" "bd_disk" {
  name             = "iac-bd.qcow2"
  pool             = var.libvirt_pool_name
  base_volume_name = var.imagen_bd
  base_volume_pool = var.libvirt_pool_name
  format           = "qcow2"
}

resource "libvirt_cloudinit_disk" "bd_cloudinit" {
  name = "iac-bd-cloudinit.iso"
  pool = var.libvirt_pool_name
  user_data = templatefile("${path.module}/cloud-init/user-data.yaml.tftpl", {
    hostname = "bd"
    usuario  = var.usuario
    ssh_key  = local.ssh_key
  })
  network_config = templatefile("${path.module}/cloud-init/network-config.yaml.tftpl", {
    mac_nat   = local.mac_bd_nat
    mac_datos = local.mac_bd_datos
    ip_datos  = var.ip_datos_bd
  })
}

resource "libvirt_domain" "bd" {
  name      = "iac-bd"
  memory    = var.memoria_bd
  vcpu      = 1
  cloudinit = libvirt_cloudinit_disk.bd_cloudinit.id

  cpu {
    mode = "host-passthrough"
  }

  network_interface {
    network_id     = libvirt_network.red_nat.id
    mac            = local.mac_bd_nat
    wait_for_lease = true
  }

  network_interface {
    network_id = libvirt_network.red_datos.id
    mac        = local.mac_bd_datos
  }

  disk {
    volume_id = libvirt_volume.bd_disk.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}
