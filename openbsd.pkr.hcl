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

source "qemu" "install" {
  vm_name          = "openbsd-${source.name}.raw"
  output_directory = "output/${source.name}"

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
    name = "base"
    http_content = {
      "/install.conf" = templatefile("install.conf.pkrtpl", {
        "ssh_public_key" : data.sshkey.install.public_key,
        "sets" : "-man* -game* -x* -comp*"
      })
    }
  }
  source "source.qemu.install" {
    name = "full"
    http_content = {
      "/install.conf" = templatefile("install.conf.pkrtpl", {
        "ssh_public_key" : data.sshkey.install.public_key,
        "sets" : "*",
      })
    }
  }
  provisioner "file" {
    source      = "cloud-init.sh"
    destination = "/usr/local/sbin/cloud-init"
  }
  provisioner "shell" {
    scripts = [
      "scripts/syspatch.sh",
      "scripts/cloud.sh",
      "scripts/cleanup.sh",
    ]
  }
}
