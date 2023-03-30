module "vms" {
  source = "./vms"
  proxmox_vm_default_password = var.proxmox_vm_default_password
  ansible_playbooks_location = var.ansible_playbooks_location
}

variable "proxmox_vm_default_password" {
  type = string
}
