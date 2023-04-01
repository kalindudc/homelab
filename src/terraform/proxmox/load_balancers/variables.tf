variable "proxmox_vm_default_password" {
  type = string
}

variable "ansible_playbooks_location" {
  type = string
  default = "../../../ansible/playbooks"
}

variable "ssh_key" {
  type = string
}
