packer {
  required_plugins {
    sshkey = {
      version = ">= 1.0.0"
      source  = "github.com/ivoronin/sshkey"
    }
  }
}

data "sshkey" "install" {
  type = "ed25519"
}

locals {
  ver        = "7.1"
  tag        = replace(local.ver, ".", "")
  image_name = "openbsd-${local.tag}-${formatdate("YYYYMMDDhhmm", timestamp())}"
}
/*
 # pip3 install -U bcrypt && python3
 >> import bcrypy
 >> bcrypt.hashpw(b'password', bcrypt.gensalt(14)).decode('utf-8')
 # export PKR_VAR_root_password='$2b$...'
*/
variable "root_password" {
  type    = string
  default = "*"
}

source "qemu" "install" {
  vm_name          = source.name
  output_directory = "output"

  iso_checksum = "file:https://ftp.openbsd.org/pub/OpenBSD/${local.ver}/amd64/SHA256"
  iso_url      = "https://ftp.openbsd.org/pub/OpenBSD/${local.ver}/amd64/install${local.tag}.iso"

  disk_size      = "5G"
  disk_interface = "virtio"
  cpus           = 1
  headless       = true
  format         = "raw"

  boot_command = [
    "A<enter><wait>",
    "http://{{ .HTTPIP }}:{{ .HTTPPort }}/install.conf<enter>"
  ]
  boot_wait        = "20s"
  shutdown_command = "halt -p"

  ssh_private_key_file = data.sshkey.install.private_key_path
  ssh_username         = "root"
  ssh_timeout          = "15m"

  /*
  vnc_bind_address     = "0.0.0.0"
  vnc_port_min         = "5900"
  vnc_port_max         = "5900"
  */
}

build {
  source "source.qemu.install" {
    name = "base.raw"
    http_content = {
      "/install.conf" = templatefile("install.conf.pkrtpl", {
        "root_password" : var.root_password,
        "ssh_public_key" : data.sshkey.install.public_key,
        "sets" : "-man* -game* -x* -comp*"
      })
    }
  }
  source "source.qemu.install" {
    name = "full.raw"
    http_content = {
      "/install.conf" = templatefile("install.conf.pkrtpl", {
        "root_password" : var.root_password,
        "ssh_public_key" : data.sshkey.install.public_key,
        "sets" : "*",
      })
    }
  }
  /*
  provisioner "file" {
    source      = "cloud-init.sh"
    destination = "/usr/local/sbin/cloud-init"
  }
  */
  provisioner "shell" {
    scripts = [
      "post-install/syspatch.sh",
      // "post-install/cloud.sh",
      "post-install/cleanup.sh",
    ]
  }
}
