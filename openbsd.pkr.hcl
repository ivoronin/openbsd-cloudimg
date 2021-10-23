packer {
  required_plugins {
    sshkey = {
      version = ">= 0.1.0"
      source  = "github.com/ivoronin/sshkey"
    }
    amazon = {
      version = ">= 0.0.1"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

data "sshkey" "install" {
}

locals {
  ver        = "6.9"
  tag        = replace(local.ver, ".", "")
  image_name = "openbsd-${local.tag}-${formatdate("YYYYMMDDhhmm", timestamp())}"
}

source "qemu" "install" {
  vm_name = "disk.raw"

  iso_checksum = "file:https://ftp.openbsd.org/pub/OpenBSD/${local.ver}/amd64/SHA256"
  iso_url      = "https://ftp.openbsd.org/pub/OpenBSD/${local.ver}/amd64/install${local.tag}.iso"

  disk_size = "5G"
  cpus      = 2
  headless  = true
  format    = "raw"

  boot_command = [
    "A<enter><wait>",
    "http://{{ .HTTPIP }}:{{ .HTTPPort }}/install.conf<enter>"
  ]
  boot_wait = "20s"
  http_content = {
    "/install.conf" = templatefile("install.conf.pkrtpl", { "ssh_public_key" : data.sshkey-sshkey.install.public_key })
  }
  shutdown_command = "halt -p"

  ssh_private_key_file = data.sshkey-sshkey.install.private_key_path
  ssh_username         = "root"

  // vnc_bind_address     = "0.0.0.0"
  // vnc_port_max         = "5900"
  // vnc_port_min         = "5900"
}
