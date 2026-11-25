# Informe de pruebas

Todas las órdenes se lanzan desde mi equipo, en el directorio `ansible/` del repositorio, salvo que se indique otra cosa. Las órdenes `ansible` llevan `--ask-vault-pass` porque las variables incluyen contraseñas cifradas con Ansible Vault (modificación 3): hay que escribir la contraseña de Vault cuando la pida.

Antes de empezar, en la terminal no debe estar definida la variable `ANSIBLE_VAULT_PASSWORD_FILE` (la comprobación 3.2 necesita que Ansible no tenga la contraseña):

```
unset ANSIBLE_VAULT_PASSWORD_FILE
```

## Modificación 1: almacenamiento persistente y copias de seguridad para MariaDB

Qué demuestra: los datos de MariaDB están en un disco propio con LVM y hay un segundo disco para copias, y una copia hecha con el script de la receta se puede restaurar después de perder los datos.

### 1.1. Los datos y las copias están en sus propios discos

* Dónde: en mi equipo, en el directorio `ansible/`

* Orden:
  
  ```
  ansible bd -b --ask-vault-pass -a "findmnt -n -o SOURCE,TARGET /var/lib/mariadb"
  ansible bd -b --ask-vault-pass -a "findmnt -n -o SOURCE,TARGET /var/backups/mariadb"
  ansible bd -b --ask-vault-pass -a "crontab -l"
  ```

* Resultado esperado:
  
  * La primera muestra `/dev/mapper/vg_datos-lv_mysql /var/lib/mariadb`: el directorio de datos de MariaDB es un volumen lógico de LVM.
  * La segunda muestra `/dev/vdc /var/backups/mariadb`: las copias van a otro disco.
  * La tercera muestra la línea `0 3 * * * /usr/local/sbin/backup-mariadb.sh >> /var/log/backup-mariadb.log 2>&1`: la copia diaria está programada.

* Salida en el ensayo:
  
  ```
  $ ansible bd -b --ask-vault-pass -a "findmnt -n -o SOURCE,TARGET /var/lib/mariadb"
  bd | CHANGED | rc=0 >>
  /dev/mapper/vg_datos-lv_mysql /var/lib/mariadb
  
  $ ansible bd -b --ask-vault-pass -a "findmnt -n -o SOURCE,TARGET /var/backups/mariadb"
  bd | CHANGED | rc=0 >>
  /dev/vdc /var/backups/mariadb
  
  $ ansible bd -b --ask-vault-pass -a "crontab -l"
  bd | CHANGED | rc=0 >>
  #Ansible: Copia de seguridad de MariaDB
  0 3 * * * /usr/local/sbin/backup-mariadb.sh >> /var/log/backup-mariadb.log 2>&1
  ```

### 1.2. Una copia se puede restaurar después de perder los datos

La copia diaria la lanza cron a las 03:00; aquí se lanza a mano el mismo script.

* Dónde: en mi equipo, en el directorio `ansible/`

* Orden:
  
  ```
  ansible bd -b --ask-vault-pass -a "mariadb guestbook -e \"INSERT INTO messages (name, message, created_at) VALUES ('prueba', 'mensaje antes de la copia', NOW())\""
  ansible bd -b --ask-vault-pass -a "/usr/local/sbin/backup-mariadb.sh"
  ansible bd -b --ask-vault-pass -a "mariadb guestbook -e 'DELETE FROM messages'"
  ansible bd -b --ask-vault-pass -a "mariadb guestbook -e 'SELECT COUNT(*) FROM messages'"
  ansible bd -b --ask-vault-pass -m shell -a "zcat \$(ls -t /var/backups/mariadb/*.sql.gz | head -1) | mariadb guestbook"
  ansible bd -b --ask-vault-pass -a "mariadb guestbook -e 'SELECT name, message FROM messages'"
  ```

* Resultado esperado:
  
  * El script responde `Copia creada: /var/backups/mariadb/guestbook-AAAAMMDD-HHMM.sql.gz`, con la fecha y la hora de la prueba.
  * Después de borrar, el `COUNT(*)` es `0`.
  * Después de restaurar, el último `SELECT` vuelve a mostrar la fila `prueba    mensaje antes de la copia`, junto con los mensajes que hubiera en la aplicación antes de la copia.

* Salida en el ensayo:
  
  ```
  $ ansible bd -b --ask-vault-pass -a "mariadb guestbook -e \"INSERT INTO messages (name, message, created_at) VALUES ('prueba', 'mensaje antes de la copia', NOW())\""
  bd | CHANGED | rc=0 >>
  
  $ ansible bd -b --ask-vault-pass -a "/usr/local/sbin/backup-mariadb.sh"
  bd | CHANGED | rc=0 >>
  2026-11-25 12:01:46 Copia creada: /var/backups/mariadb/guestbook-20261125-1201.sql.gz
  
  $ ansible bd -b --ask-vault-pass -a "mariadb guestbook -e 'DELETE FROM messages'"
  bd | CHANGED | rc=0 >>
  
  $ ansible bd -b --ask-vault-pass -a "mariadb guestbook -e 'SELECT COUNT(*) FROM messages'"
  bd | CHANGED | rc=0 >>
  COUNT(*)
  0
  
  $ ansible bd -b --ask-vault-pass -m shell -a "zcat \$(ls -t /var/backups/mariadb/*.sql.gz | head -1) | mariadb guestbook"
  bd | CHANGED | rc=0 >>
  
  $ ansible bd -b --ask-vault-pass -a "mariadb guestbook -e 'SELECT name, message FROM messages'"
  bd | CHANGED | rc=0 >>
  name    message
  Gabriel    Hola, este es el video de la mod 3
  prueba    mensaje antes de la copia
  ```

## Modificación 2: bd aislada detrás de web (router/NAT y cortafuegos de lista blanca)

Qué demuestra: `bd` solo está en la red de datos y sale a Internet a través de `web`, y el cortafuegos rechaza lo que no está en la lista blanca.

### 2.1. bd solo está en la red de datos y sale a Internet a través de web

* Dónde: en mi equipo, en el directorio `ansible/`

* Orden:
  
  ```
  ansible bd --ask-vault-pass -a "ip -br -4 addr"
  ansible bd --ask-vault-pass -a "ip route show default"
  ansible bd --ask-vault-pass -a "curl -s -o /dev/null -w %{http_code} https://deb.debian.org"
  ```

* Resultado esperado:
  
  * La primera muestra solo `lo` (`127.0.0.1/8`) y `ens3` con `10.0.100.20/24`: ninguna dirección de la red NAT `192.168.123.0/24`.
  * La segunda muestra `default via 10.0.100.10 dev ens3 proto static`: la puerta de enlace es `web`.
  * La tercera devuelve `200`: aun sin interfaz en la red NAT, `bd` llega a Internet gracias al NAT de `web`.

* Salida en el ensayo (25/11/2026):
  
  ```
  $ ansible bd --ask-vault-pass -a "ip -br -4 addr"
  bd | CHANGED | rc=0 >>
  lo               UNKNOWN        127.0.0.1/8
  ens3             UP             10.0.100.20/24
  
  $ ansible bd --ask-vault-pass -a "ip route show default"
  bd | CHANGED | rc=0 >>
  default via 10.0.100.10 dev ens3 proto static
  
  $ ansible bd --ask-vault-pass -a "curl -s -o /dev/null -w %{http_code} https://deb.debian.org"
  bd | CHANGED | rc=0 >>
  200
  ```

### 2.2. Lo que no está permitido se rechaza

* Dónde: en mi equipo (la primera orden, desde cualquier directorio) y en el directorio `ansible/` (las otras dos)

* Orden:
  
  ```
  ssh -o ConnectTimeout=5 -o BatchMode=yes gabriel@10.0.100.20 true
  ansible bd --ask-vault-pass -a "curl -sS -m 5 -o /dev/null -w %{http_code} http://portquiz.net"
  ansible bd --ask-vault-pass -a "curl -sS -m 5 -o /dev/null -w %{http_code} http://portquiz.net:8080"
  ```

* Resultado esperado:
  
  * El `ssh` directo desde mi equipo a `bd` falla con `ssh: connect to host 10.0.100.20 port 22: Connection timed out`: `bd` no es accesible desde fuera.
  * La segunda (puerto 80, permitido en la lista blanca de `web`) devuelve `200`.
  * La tercera, al mismo servidor pero al puerto 8080 (no permitido), falla con `bd | FAILED | rc=28` y `000curl: (28) Connection timed out after 5001 milliseconds` (los milisegundos pueden variar un poco; `000` es el código HTTP vacío porque no hay respuesta): `web` descarta el paquete. `portquiz.net` responde en cualquier puerto, así que la diferencia la pone el cortafuegos.

* Salida en el ensayo:
  
  ```
  $ ssh -o ConnectTimeout=5 -o BatchMode=yes gabriel@10.0.100.20 true
  ssh: connect to host 10.0.100.20 port 22: Connection timed out
  
  $ ansible bd --ask-vault-pass -a "curl -sS -m 5 -o /dev/null -w %{http_code} http://portquiz.net"
  bd | CHANGED | rc=0 >>
  200
  
  $ ansible bd --ask-vault-pass -a "curl -sS -m 5 -o /dev/null -w %{http_code} http://portquiz.net:8080"
  [ERROR]: Task failed: Module failed: non-zero return code
  ...
  bd | FAILED | rc=28 >>
  000curl: (28) Connection timed out after 5001 millisecondsnon-zero return code
  ```

## Modificación 3: HTTPS, phpMyAdmin y contraseñas cifradas con Ansible Vault

Qué demuestra: la aplicación y phpMyAdmin solo se sirven por HTTPS, y las credenciales están protegidas: cifradas en el repositorio y con un usuario de phpMyAdmin que solo puede ver la base de datos de la aplicación.

### 3.1. La aplicación y phpMyAdmin se sirven por HTTPS

* Dónde: en mi equipo (con la línea de `www.gabrielmerencio.org` en `/etc/hosts`, igual que para la aplicación)

* Orden:
  
  ```
  curl -sI http://www.gabrielmerencio.org | grep -E "^HTTP|^Location"
  curl -skI https://www.gabrielmerencio.org | head -1
  curl -skI https://www.gabrielmerencio.org/phpmyadmin/ | head -1
  echo | openssl s_client -connect www.gabrielmerencio.org:443 -servername www.gabrielmerencio.org 2>/dev/null | openssl x509 -noout -subject
  ```

* Resultado esperado:
  
  * La primera muestra `HTTP/1.1 301 Moved Permanently` y `Location: https://www.gabrielmerencio.org/`: por HTTP solo se redirige.
  * La segunda y la tercera muestran `HTTP/1.1 200 OK`: la aplicación y phpMyAdmin responden por HTTPS.
  * La cuarta muestra `subject=CN=www.gabrielmerencio.org`: el certificado que genera la receta.

* Salida en el ensayo:
  
  ```
  $ curl -sI http://www.gabrielmerencio.org | grep -E "^HTTP|^Location"
  HTTP/1.1 301 Moved Permanently
  Location: https://www.gabrielmerencio.org/
  
  $ curl -skI https://www.gabrielmerencio.org | head -1
  HTTP/1.1 200 OK
  
  $ curl -skI https://www.gabrielmerencio.org/phpmyadmin/ | head -1
  HTTP/1.1 200 OK
  
  $ echo | openssl s_client -connect www.gabrielmerencio.org:443 -servername www.gabrielmerencio.org 2>/dev/null | openssl x509 -noout -subject
  subject=CN=www.gabrielmerencio.org
  ```

### 3.2. Las credenciales están protegidas

* Dónde: en mi equipo, en el directorio `ansible/`

* Orden:
  
  ```
  head -1 group_vars/all/vault.yaml
  ansible-playbook site.yaml
  ansible web --ask-vault-pass -m shell -a "mariadb -h {{ ip_datos_bd }} -u {{ pma_usuario }} -p'{{ pma_password }}' -e 'SHOW DATABASES; SELECT user FROM mysql.user'"
  ```

* Resultado esperado:
  
  * La primera muestra `$ANSIBLE_VAULT;1.1;AES256`: las contraseñas del repositorio están cifradas.
  
  * La segunda, sin la contraseña de Vault, se para con `[ERROR]: Attempting to decrypt but no vault secrets found.` sin tocar ninguna máquina.
  
  * La tercera se conecta desde `web` a MariaDB en `bd` con el usuario de phpMyAdmin (la contraseña la pone Ansible desde Vault, no aparece en la orden). Falla con `web | FAILED | rc=1`: `SHOW DATABASES` solo lista `guestbook` e `information_schema`, y la consulta a `mysql.user` se rechaza porque el usuario de phpMyAdmin no puede ver nada más que la base de datos de la aplicación:
    
    ```
    Database
    guestbook
    information_schema
    ...
    ERROR 1142 (42000) at line 1: SELECT command denied to user 'phpmyadmin'@'_gateway' for table `mysql`.`user`
    ```
    
    `_gateway` es el nombre con el que `bd` resuelve su puerta de enlace, es decir, `web` (`10.0.100.10`).

* Salida en el ensayo:
  
  ```
  $ head -1 group_vars/all/vault.yaml
  $ANSIBLE_VAULT;1.1;AES256
  
  $ ansible-playbook site.yaml
  
  PLAY [Router y cortafuegos en web] *********************************************
  [ERROR]: Attempting to decrypt but no vault secrets found.
  
  $ ansible web --ask-vault-pass -m shell -a "mariadb -h {{ ip_datos_bd }} -u {{ pma_usuario }} -p'{{ pma_password }}' -e 'SHOW DATABASES; SELECT user FROM mysql.user'"
  [ERROR]: Task failed: Module failed: non-zero return code
  ...
  web | FAILED | rc=1 >>
  Database
  guestbook
  information_schema--------------
  SELECT user FROM mysql.user
  --------------
  
  ERROR 1142 (42000) at line 1: SELECT command denied to user 'phpmyadmin'@'_gateway' for table `mysql`.`user`non-zero return code
  ```
