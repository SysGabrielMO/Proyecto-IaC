# Proyecto 1: Infraestructura como código

Escenario en libvirt/KVM creado con **Terraform** y configurado con **Ansible**. Despliega la aplicación PHP [guestbook](https://github.com/josedom24/guestbook_php) con dos máquinas:

| Máquina | Sistema | Función |
|---|---|---|
| `web` | Debian 13 | Apache + PHP |
| `bd` | Ubuntu 26.04 | MariaDB con disco de datos LVM y copias de seguridad diarias |

## Esquema

```
              192.168.123.0/24 (iac-nat, NAT + DHCP)
      host .1 ---------+------------------+
                       |                  |
                  +----+----+        +----+----+
                  |   web   |        |   bd    |
                  +----+----+        +----+----+
                       |  10.0.100.10     |  10.0.100.20
                       +------------------+
                  10.0.100.0/24 (iac-datos, aislada)
```

La red `iac-datos` está aislada: solo `web` y `bd` se ven entre sí y MariaDB escucha únicamente en `10.0.100.20`.

## Requisitos

En la máquina anfitriona:

- Linux con **libvirt/KVM** funcionando (`qemu:///system`) y tu usuario en el grupo `libvirt`.
- **Terraform** ≥ 1.6 (proveedores `dmacvicar/libvirt` 0.8.3 y `hashicorp/local`, que se descargan con `terraform init`).
- **Ansible** y las colecciones:
  ```
  ansible-galaxy collection install community.general ansible.posix community.mysql
  ```
- Una clave SSH (por defecto `~/.ssh/id_rsa.pub`).
- Las imágenes base en el pool de libvirt `default` (`/var/lib/libvirt/images`), con estos nombres exactos:
  - `debian-13-genericcloud-amd64.qcow2`
  - `ubuntu-26.04-server-cloudimg-amd64.qcow2`
- El rango `192.168.123.0/24` libre en el anfitrión.

## Uso

```
git clone https://github.com/SysGabrielMO/Proyecto-IaC.git
cd Proyecto-IaC/terraform
terraform init
terraform apply          # crea redes, discos y máquinas y genera ansible/hosts

cd ../ansible
ansible-playbook site.yaml
```

Si `bd` responde `Connection refused` justo tras el `apply`, espera medio minuto (cloud-init aún está terminando) y repite el playbook.

Una segunda ejecución del playbook debe dar `changed=0`.

### Acceder a la aplicación

El virtual host responde al nombre `www.gabrielmerencio.org`. Añade a `/etc/hosts` del anfitrión la IP de `web` (la muestra `terraform output ips`):

```
<IP_web>  www.gabrielmerencio.org
```

Después abre `http://www.gabrielmerencio.org`.

## Variables

**Terraform** (`terraform/variables.tf`): usuario (`usuario`, por defecto `gabriel`), ruta de la clave pública (`ssh_public_key`), imágenes (`imagen_web`, `imagen_bd`), memoria, tamaño de los discos (`tamano_disco`, `tamano_disco_datos`, `tamano_disco_backup`) y direcciones de la red de datos.

**Ansible** (`ansible/group_vars/`): base de datos y usuario de la aplicación, paquetes, dominio del virtual host y, para `bd`, discos, volumen LVM, ruta de datos y política de copias (hora, retención).

## Estructura

```
terraform/            redes, discos, máquinas, cloud-init e inventario
ansible/
  site.yaml           playbook principal
  group_vars/         variables por grupo
  roles/
    commons/          configuración común (cloud-init, actualizaciones, paquetes)
    bd/               LVM + MariaDB
    backup/           disco de copias, script y cron
    web/              Apache, PHP y aplicación
```

El inventario `ansible/hosts` lo genera Terraform con las IPs que reparte DHCP.

## Almacenamiento y copias (modificación 1)

- Disco de datos (`vdb`) con LVM, montado en `/var/lib/mariadb`. Sobrevive a la recreación de la máquina `bd`.
- Disco de copias (`vdc`) montado en `/var/backups/mariadb`.
- Copia diaria a las 03:00 (hora de `bd`) con `mariadb-dump`, comprimida y con retención de 7 días.
- Restaurar una copia:
  ```
  zcat /var/backups/mariadb/<fichero>.sql.gz | mariadb guestbook
  ```
- Ampliar el volumen en caliente:
  ```
  ansible bd -b -a "lvextend -r -l +100%FREE /dev/vg_datos/lv_mysql"
  ```
- Recrear solo `bd` conservando los datos:
  ```
  terraform apply \
    -replace=libvirt_domain.bd \
    -replace=libvirt_volume.bd_disk \
    -replace=libvirt_cloudinit_disk.bd_cloudinit
  ```

## Destruir el escenario

```
cd terraform
terraform destroy
```

Esto borra también los discos de datos y de copias.
