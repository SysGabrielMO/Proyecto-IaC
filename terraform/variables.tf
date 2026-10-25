variable "red_nat_cidr" {
  description = "Rango de la red NAT con DHCP"
  type        = string
  default     = "192.168.123.0/24"
}

variable "libvirt_pool_name" {
  description = "Pool de libvirt donde están las imágenes base"
  type        = string
  default     = "default"
}

variable "imagen_web" {
  description = "Imagen base del servidor web (Debian 13)"
  type        = string
  default     = "debian-13-genericcloud-amd64.qcow2"
}

variable "imagen_bd" {
  description = "Imagen base del servidor de base de datos (Ubuntu 26.04)"
  type        = string
  default     = "ubuntu-26.04-server-cloudimg-amd64.qcow2"
}

variable "memoria_web" {
  description = "Memoria del servidor web en MiB"
  type        = number
  default     = 2048
}

variable "memoria_bd" {
  description = "Memoria del servidor de base de datos en MiB"
  type        = number
  default     = 2048
}

variable "ip_datos_web" {
  description = "IP estática de web en la red de datos"
  type        = string
  default     = "10.0.100.10"
}

variable "ip_datos_bd" {
  description = "IP estática de bd en la red de datos"
  type        = string
  default     = "10.0.100.20"
}

variable "usuario" {
  description = "Usuario que crea cloud-init y con el que se conecta Ansible"
  type        = string
  default     = "gabriel"
}

variable "ssh_public_key" {
  description = "Ruta a la clave SSH pública que se instala en las máquinas"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
