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

variable "build" {
  type        = string
  description = "Build target whose patch-set to apply (e.g. aws)"
}

variable "iso_checksum" {
  type        = string
  description = "Pinned installer ISO checksum"
}

variable "accelerator" {
  type    = string
  default = "kvm"
}

variable "efi_code" {
  type    = string
  default = ""
}

variable "efi_vars" {
  type    = string
  default = ""
}

variable "cpus" {
  type        = number
  description = "vCPUs for the builder; 4 beats 8 under hvf (emulated GIC = timer/IPI VM-exit storm). Bump on a KVM host."
  default     = 4
}

# Throwaway builder VM with the comp toolchain; never shipped, so SSH provisioning is fine.
data "sshkey" "build" {
  type = "ed25519"
}

locals {
  tag = replace(var.version, ".", "")
  # arm64 builder is UEFI; amd64 builder is BIOS - the proven boot path (the amd64
  # install.iso boots BIOS), and the throwaway builder's firmware never ships anyway.
  use_efi = var.arch == "arm64"
  qemu_binary = {
    amd64 = "qemu-system-x86_64"
    arm64 = "qemu-system-aarch64"
  }
  machine_type = {
    amd64 = "pc"
    arm64 = "virt"
  }
  # arm64 virt wiring (see image.pkr.hcl), no cd1.
  qemuargs = {
    amd64 = []
    arm64 = [
      ["-cpu", var.accelerator == "tcg" ? "cortex-a72" : "host"],
      ["-device", "virtio-gpu-pci"],
      ["-device", "qemu-xhci"], ["-device", "usb-kbd"],
      ["-device", "virtio-scsi-pci,id=scsi0"],
      ["-device", "scsi-hd,bus=scsi0.0,drive=drive0,bootindex=0"],
      ["-device", "scsi-cd,bus=scsi0.0,drive=cdrom0,bootindex=1"],
    ]
  }
}

source "qemu" "build" {
  vm_name          = "builder-${var.version}-${var.arch}-${var.build}.img"
  output_directory = "output/builder/${var.arch}/${var.version}/${var.build}"

  iso_checksum    = var.iso_checksum
  iso_url         = "https://cdn.openbsd.org/pub/OpenBSD/${var.version}/${var.arch}/install${local.tag}.iso"
  iso_target_path = "iso/openbsd-${var.version}-${var.arch}.iso"

  http_content = {
    "/install.conf" = templatefile("build.conf.pkrtpl", {
      "ssh_public_key" : data.sshkey.build.public_key,
      "disk_answer" : local.use_efi ? "G" : "W"
    })
  }

  qemu_binary       = local.qemu_binary[var.arch]
  machine_type      = local.machine_type[var.arch]
  efi_firmware_code = local.use_efi ? var.efi_code : ""
  efi_firmware_vars = local.use_efi ? var.efi_vars : ""
  qemuargs          = local.qemuargs[var.arch]
  accelerator       = var.accelerator
  disk_size         = "40G"
  disk_interface    = var.arch == "arm64" ? "virtio-scsi" : "virtio"
  cdrom_interface   = var.arch == "arm64" ? "virtio-scsi" : ""
  cpus              = var.cpus
  memory            = 8192
  headless          = true
  format            = "raw"

  boot_command = [
    "A<enter><wait>",
    "http://{{ .HTTPIP }}:{{ .HTTPPort }}/install.conf<enter>"
  ]
  boot_wait        = var.accelerator == "tcg" ? "60s" : "30s"
  shutdown_command = "halt -p"

  ssh_private_key_file = data.sshkey.build.private_key_path
  ssh_username         = "root"
  ssh_timeout          = "20m"

  vnc_port_min = 5901
  vnc_port_max = 5901
}

build {
  sources = ["source.qemu.build"]

  # upload the build/ tree, then run the target's build.sh
  provisioner "file" {
    source      = "build"
    destination = "/home"
  }
  provisioner "shell" {
    inline = [
      "ksh /home/build/${var.build}/build.sh ${var.version} ${var.build}",
    ]
  }
  # pull the finished site set: site<tag>.tgz + SHA256
  provisioner "file" {
    direction   = "download"
    source      = "/home/site/site${local.tag}.tgz"
    destination = "output/sets/${var.arch}/${var.version}/${var.build}/"
  }
  provisioner "file" {
    direction   = "download"
    source      = "/home/site/SHA256"
    destination = "output/sets/${var.arch}/${var.version}/${var.build}/"
  }
}
