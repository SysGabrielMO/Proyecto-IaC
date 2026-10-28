output "ips" {
  description = "Direcciones IP de las máquinas"
  value = {
    web = {
      nat   = libvirt_domain.web.network_interface[0].addresses[0]
      datos = var.ip_datos_web
    }
    bd = {
      nat   = libvirt_domain.bd.network_interface[0].addresses[0]
      datos = var.ip_datos_bd
    }
  }
}
