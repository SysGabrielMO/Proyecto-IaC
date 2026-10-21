# Proyecto-IaC
Despliegue de un libro de visitas en PHP con MariaDB sobre libvirt/KVM.
El escenario se crea con Terraform y se configura con Ansible.

## Requisitos

- libvirt / KVM
- Terraform
- Ansible

## Despliegue

```bash
cd terraform
terraform init
terraform apply
cd ../ansible
ansible-playbook site.yaml
```
