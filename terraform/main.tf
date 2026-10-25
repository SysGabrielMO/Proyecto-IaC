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
