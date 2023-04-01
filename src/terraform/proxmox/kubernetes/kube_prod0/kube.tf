locals {
  ip_prefix = 1
}

resource "proxmox_vm_qemu" "kube-server-head" {

  target_node = "${var.hosts[0].target_node}"
  vmid = "401"
  name = "${var.hosts[0].name}.server.collie"
  desc = "This is a server node for kube api server"

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

  ipconfig0 = "ip=${var.hosts[0].ip}/16,gw=10.0.0.1"

  ciuser = "administrator"
  cipassword = "${var.proxmox_vm_default_password}"

  sshkeys = "${var.ssh_key}"

  connection {
    host = "${var.hosts[0].ip}"
    user = "administrator"
    private_key = file("~/.ssh/id_rsa")
    agent = false
    timeout = "3m"
  }

  provisioner "remote-exec" {
    inline = ["while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 5; done"]
  }

  provisioner "remote-exec" {
    inline = ["echo ${var.proxmox_vm_default_password} | sudo usermod -aG docker $USER"]
  }

  provisioner "local-exec" {
    command =  "echo 'Sleep for 60 seconds...' && sleep 60 && echo 'Done sleeping...'"
  }

  provisioner "remote-exec" {
    inline = ["curl -sfL https://get.k3s.io | sh -s - server --token=${var.kube_token} --tls-san kube.homelab --tls-san ${var.lb_ip} --cluster-init"]
  }
}

resource "proxmox_vm_qemu" "kube-server-node" {
  depends_on = [proxmox_vm_qemu.kube-server-head]

  for_each = {for i, vm in slice(var.hosts, 1, length(var.hosts)): i => vm}

  target_node = each.value.target_node
  vmid = "40${each.key + 1 + local.ip_prefix}"
  name = "${each.value.name}.server.${each.value.target_node}"
  desc = "This is a server node for kube api server"

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

  ipconfig0 = "ip=${each.value.ip}/16,gw=10.0.0.1"

  ciuser = "administrator"
  cipassword = "${var.proxmox_vm_default_password}"

  sshkeys = "${var.ssh_key}"

  connection {
    host = "${each.value.ip}}"
    user = "administrator"
    private_key = file("~/.ssh/id_rsa")
    agent = false
    timeout = "3m"
  }

  provisioner "remote-exec" {
    inline = ["while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 5; done"]
  }

  provisioner "remote-exec" {
    inline = ["echo ${var.proxmox_vm_default_password} | sudo usermod -aG docker $USER"]
  }

  provisioner "local-exec" {
    command =  "echo 'Sleep for 60 seconds...' && sleep 60 && echo 'Done sleeping...'"
  }

  provisioner "remote-exec" {
    inline = ["curl -sfL https://get.k3s.io | sh -s - server --token=${var.kube_token} --tls-san kube.homelab --tls-san ${var.lb_ip} --server https://${var.hosts[0].ip}:6443"]
  }
}
