locals {
  ip_prefix = 100
  vms = [
    {
      name = "lb-01"
      target_node = "collie"
    }
  ]
}

resource "proxmox_vm_qemu" "lb-vm" {
  for_each = {for i, vm in local.vms: i => vm}

  target_node = each.value.target_node
  vmid = "20${each.key + 1}"
  name = "${each.value.name}.server.${each.value.target_node}"
  desc = "This is a vm for a load balancer"

  boot = "order=net0;virtio0;ide0"

  onboot = true
  clone = "${local.vm_template_ubuntu_jammy}"
  agent = 1

  cores = 1
  sockets = 1
  cpu = "host"

  memory = 1024

  qemu_os = "l26"

  network {
    bridge = "vmbr0"
    model  = "virtio"
  }

  disk {
    storage = "local-lvm"
    type = "virtio"
    size = "20G"
    backup  = 0
    discard = "on"
    iothread = 0
  }

  lifecycle {
    ignore_changes  = [
      network,
      desc
    ]
  }

  os_type = "cloud-init"

  ipconfig0 = "ip=192.168.100.${local.ip_prefix + each.key + 1}/22,gw=192.168.100.1"

  ciuser = "administrator"
  cipassword = "${var.proxmox_vm_default_password}"

  sshkeys = "${local.ssh_key}"

  connection {
    host = "192.168.100.${local.ip_prefix + each.key + 1}"
    user = "administrator"
    private_key = file("~/.ssh/id_rsa")
    agent = false
    timeout = "3m"
  }

  provisioner "remote-exec" {
    inline = [ "echo 'Redy to go...'"]
  }

  provisioner "local-exec" {
    command =  "echo 'Sleep for 60 seconds...' && sleep 60 && echo 'Done sleeping...'"
  }

  provisioner "local-exec" {
    working_dir = var.ansible_playbooks_location
    command = "ansible-playbook -u administrator --key-file ~/.ssh/id_rsa -i 192.168.100.${local.ip_prefix + each.key + 1}, provision-nginx.yaml"
  }

}
