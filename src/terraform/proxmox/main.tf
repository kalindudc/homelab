module "vms" {
  source = "./vms"
  proxmox_vm_default_password = var.proxmox_vm_default_password
}

variable "proxmox_vm_default_password" {
  type = string
}
