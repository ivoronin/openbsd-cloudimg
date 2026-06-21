packer {
  required_plugins {
    qemu = {
      version = "1.1.5"
      source  = "github.com/hashicorp/qemu"
    }
    sshkey = {
      version = "1.3.0"
      source  = "github.com/ivoronin/sshkey"
    }
  }
}

variable "version" {
  type        = string
  description = "OpenBSD release, e.g. 7.9"
}

variable "arch" {
  type        = string
  description = "Target architecture, e.g. amd64"
  default     = "amd64"
}

variable "iso_checksum" {
  type        = string
  description = "Pinned installer ISO checksum, e.g. sha256:abc..."
}

variable "flavor" {
  type        = string
  description = "Image flavor: base (minimal) or full (all sets)"
  default     = "base"
}

variable "accelerator" {
  type        = string
  description = "QEMU accelerator: kvm (CI), tcg, hvf or none"
  default     = "kvm"
}

data "sshkey" "install" {
  type = "ed25519"
}

locals {
  tag        = replace(var.version, ".", "")
  image_name = "openbsd-${var.version}-${var.arch}-${var.flavor}"
  sets = {
    base = "-man* -game* -x* -comp*"
    full = "*"
  }
  disk_size = {
    base = "10G"
    full = "40G"
  }
}

source "qemu" "install" {
  vm_name          = "${local.image_name}.raw"
  output_directory = "output/${var.flavor}"

  iso_checksum = var.iso_checksum
  iso_url      = "https://cdn.openbsd.org/pub/OpenBSD/${var.version}/${var.arch}/install${local.tag}.iso"

  http_content = {
    "/install.conf" = templatefile("install.conf.pkrtpl", {
      "ssh_public_key" : data.sshkey.install.public_key,
      "sets" : local.sets[var.flavor]
    })
  }

  accelerator    = var.accelerator
  disk_size      = local.disk_size[var.flavor]
  disk_interface = "virtio"
  cpus           = 1
  headless       = true
  format         = "raw"

  # boot_command and the com0 serial console (see install.conf.pkrtpl) are
  # amd64/BIOS-specific; arm64 will need a UEFI boot sequence and its own console.
  boot_command = [
    "A<enter><wait>",
    "http://{{ .HTTPIP }}:{{ .HTTPPort }}/install.conf<enter>"
  ]
  boot_wait        = "20s"
  shutdown_command = "halt -p"

  ssh_private_key_file = data.sshkey.install.private_key_path
  ssh_username         = "root"
  ssh_timeout          = "15m"
}

build {
  sources = ["source.qemu.install"]

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
