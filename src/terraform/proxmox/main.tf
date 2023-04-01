module "load_balancers" {
  source = "./load_balancers"
  proxmox_vm_default_password = var.proxmox_vm_default_password
  ansible_playbooks_location = var.ansible_playbooks_location
  ssh_key = local.ssh_key
  hosts = local.load_balancers
}

module "kube_prod0" {
  source = "./kubernetes/kube_prod0"
  proxmox_vm_default_password = var.proxmox_vm_default_password
  ansible_playbooks_location = var.ansible_playbooks_location
  ssh_key = local.ssh_key
  kube_token = var.kube_token
  hosts = local.kube_prod0
  lb_ip = local.load_balancers[0].ip
}

variable "proxmox_vm_default_password" {
  type = string
}
