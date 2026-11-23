# Proyecto 1: Infraestructura como código

Escenario en libvirt/KVM creado con **Terraform** y configurado con **Ansible**. Despliega la aplicación PHP [guestbook](https://github.com/josedom24/guestbook_php) con dos máquinas:

| Máquina | Sistema | Función |
|---|---|---|
| `web` | Debian 13 | Router/NAT de `bd`, cortafuegos, Apache + PHP por HTTPS y phpMyAdmin |
| `bd` | Ubuntu 26.04 | MariaDB con disco de datos LVM y copias de seguridad diarias, aislada en la red de datos |

## Esquema

```
              192.168.123.0/24 (iac-nat, NAT + DHCP)
      host .1 ---------+
                       |
                  +----+----+   router/NAT + cortafuegos
                  |   web   |   HTTPS (443) y HTTP -> HTTPS
                  +----+----+
                       |  10.0.100.10
                       |
                       |  10.0.100.20
                  +----+----+   sin interfaz en la red NAT
                  |   bd    |   sale a Internet a través de web
                  +---------+
                  10.0.100.0/24 (iac-datos, aislada)
```

- `bd` solo está en la red de datos. Su puerta de enlace es `web`, que hace NAT y solo le deja salir a DNS, HTTP y HTTPS.
- Las dos máquinas tienen un cortafuegos **nftables de lista blanca** (política `drop`).
- MariaDB escucha únicamente en `10.0.100.20` y solo acepta conexiones de `web`.

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
- La **contraseña de Ansible Vault** (ver más abajo).

## Uso

```
git clone https://github.com/SysGabrielMO/Proyecto-IaC.git
cd Proyecto-IaC/terraform
terraform init
terraform apply          # crea redes, discos y máquinas y genera ansible/hosts

cd ../ansible
ansible-playbook site.yaml --ask-vault-pass
```

Si `bd` responde `Connection refused` justo tras el `apply`, espera medio minuto (cloud-init aún está terminando) y repite el playbook.

Una segunda ejecución del playbook debe dar `changed=0`.

El playbook configura primero `web` como router, porque `bd` no tiene salida propia a Internet y la necesita para instalar paquetes.

### Contraseñas con Ansible Vault

Las contraseñas de MariaDB están cifradas en `ansible/group_vars/all/vault.yaml`. La contraseña de Vault no está en el repositorio. Para no escribirla en cada comando, se puede guardar en un fichero **fuera del repositorio**:

```
printf '%s\n' 'contraseña-de-vault' > ~/.vault_pass
chmod 600 ~/.vault_pass
export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass
```

Ver o cambiar las contraseñas:

```
ansible-vault view group_vars/all/vault.yaml
ansible-vault edit group_vars/all/vault.yaml
```

### Acceder a la aplicación y a phpMyAdmin

El virtual host responde al nombre `www.gabrielmerencio.org`. Añade a `/etc/hosts` del anfitrión la IP de `web` (la muestra `terraform output ips`):

```
<IP_web>  www.gabrielmerencio.org
```

- Aplicación: `https://www.gabrielmerencio.org` (`http://` redirige a `https://`).
- phpMyAdmin: `https://www.gabrielmerencio.org/phpmyadmin/`, con el usuario `phpmyadmin`. Solo se puede entrar desde la red NAT y solo ve la base de datos `guestbook`.

El certificado es autofirmado, así que el navegador mostrará un aviso la primera vez.

### Acceder a bd

Desde el anfitrión no hay ruta directa a `bd`. Ansible entra a través de `web` (`ProxyCommand` en el inventario que genera Terraform), así que basta con:

```
ansible bd -m ping
```

## Variables

**Terraform** (`terraform/variables.tf`): usuario (`usuario`, por defecto `gabriel`), ruta de la clave pública (`ssh_public_key`), imágenes (`imagen_web`, `imagen_bd`), memoria, tamaño de los discos (`tamano_disco`, `tamano_disco_datos`, `tamano_disco_backup`), direcciones de la red de datos y DNS de `bd` (`dns_bd`; vacío usa el DNS de libvirt, que funciona en redes que bloquean DNS externos).

**Ansible** (`ansible/group_vars/`):

- `all/vars.yaml`: redes, base de datos y usuarios de la aplicación y de phpMyAdmin, paquetes y puertos de salida permitidos a `bd`.
- `all/vault.yaml`: contraseñas, cifradas con Ansible Vault.
- `servidores_web.yaml`: dominio del virtual host, aplicación, certificado y plantilla del cortafuegos.
- `servidores_bd.yaml`: discos, volumen LVM, ruta de datos, política de copias y plantilla del cortafuegos.

## Estructura

```
terraform/            redes, discos, máquinas, cloud-init e inventario
ansible/
  site.yaml           playbook principal
  group_vars/         variables por grupo (all/ incluye el fichero cifrado)
  roles/
    commons/          configuración común (cloud-init, actualizaciones, paquetes)
    router/           reenvío de paquetes en web
    cortafuegos/      nftables de lista blanca en web y bd, con el NAT de web
    bd/               LVM + MariaDB y usuarios de la aplicación y de phpMyAdmin
    backup/           disco de copias, script y cron
    web/              Apache, PHP, aplicación y HTTPS
    phpmyadmin/       phpMyAdmin conectado a bd por la red de datos
```

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

## Red aislada y cortafuegos (modificación 2)

- `web`: entra SSH, HTTP y HTTPS solo desde la red NAT; reenvía el tráfico de `bd` solo a DNS (53), HTTP (80) y HTTPS (443) y le hace NAT.
- `bd`: entra SSH y MariaDB (3306) solo desde `web`.
- Ver las reglas: `ansible web -b -a "nft list ruleset"`.

## HTTPS, phpMyAdmin y Ansible Vault (modificación 3)

- Certificado autofirmado generado por Ansible en `/etc/ssl/guestbook/`, válido un año.
- El puerto 80 solo redirige a HTTPS.
- phpMyAdmin instalado desde los repositorios de Debian, conectado a MariaDB en `bd` por la red de datos y sin acceso como `root`.
- Contraseñas cifradas con Ansible Vault.

## Destruir el escenario

```
cd terraform
terraform destroy
```

Esto borra también los discos de datos y de copias.
