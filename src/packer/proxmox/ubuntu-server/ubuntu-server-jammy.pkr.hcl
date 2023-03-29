variable "proxmox_api_url" {
  type = string
}

variable "proxmox_api_token_id" {
  type = string
}

variable "proxmox_api_token_secret" {
  type = string
  sensitive = true
}

variable "node_name" {
  type = string
}

variable "vm_id" {
  type = string
}

source "proxmox" "ubuntu-server-jammy-local" {

  proxmox_url = "${var.proxmox_api_url}"
  username = "${var.proxmox_api_token_id}"
  token = "${var.proxmox_api_token_secret}"
  insecure_skip_tls_verify = true

  node = "${var.node_name}"
  vm_id = "${var.vm_id}"
  vm_name = "ubuntu-server-jammy-local"
  template_description = "Ubuntu Server jammy Image"

  iso_file = "local:iso/ubuntu-22.04.2-live-server-amd64.iso"
  iso_storage_pool = "local"
  unmount_iso = true

  qemu_agent = true

  scsi_controller = "virtio-scsi-pci"

  disks {
    disk_size = "20G"
    storage_pool = "local-lvm"
    storage_pool_type = "lvm"
    type = "virtio"
  }

  cores = "1"

  memory = "1024"

  network_adapters {
    model = "virtio"
    bridge = "vmbr0"
    firewall = "false"
  }

  cloud_init = true
  cloud_init_storage_pool = "local-lvm"

  # PACKER Boot Commands
  # https://discuss.hashicorp.com/t/proxmox-packer-ubuntu-autoinstall/45662
  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    "<bs><bs><bs><bs><wait>",
    "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
    "<f10><wait>"
  ]
  boot = "c"
  boot_wait = "5s"

  http_directory = "http"

  ssh_username = "kalindu"
  ssh_private_key_file = "~/.ssh/id_rsa"

  ssh_timeout = "25m"
}

build {
  # https://github.com/ChristianLempa/boilerplates
  name = "ubuntu-server-jammy-local"
  sources = ["source.proxmox.ubuntu-server-jammy-local"]

  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "sudo rm /etc/ssh/ssh_host_*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo apt -y autoremove --purge",
      "sudo apt -y clean",
      "sudo apt -y autoclean",
      "sudo cloud-init clean",
      "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
      "sudo sync"
    ]
  }

  provisioner "file" {
    source = "files/99-pve.cfg"
    destination = "/tmp/99-pve.cfg"
  }

  provisioner "shell" {
    inline = [ "sudo cp /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg" ]
  }

  # docker
  provisioner "shell" {
    inline = [
      "sudo apt-get install -y ca-certificates curl gnupg lsb-release",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get -y update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io"
    ]
  }
}
