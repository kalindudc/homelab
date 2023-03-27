resource "proxmox_vm_qemu" "border_collie" {

  target_node = "collie"
  vmid = "201"
  name = "border.collie"
  desc = "This cloned vm from ${local.vm_template_ubuntu_jammy}"

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
    backup  = true
    discard = "on"
    iothread = 1
  }

  lifecycle {
    ignore_changes  = [
      network,
      desc
    ]
  }

  os_type = "cloud-init"

  ipconfig0 = "ip=192.168.101.1/22,gw=192.168.100.1"

  ciuser = "administrator"
  cipassword = "${var.proxmox_vm_default_password}"

  sshkeys = "${local.ssh_key}"

}
