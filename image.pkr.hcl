packer {
  required_plugins {
    qemu = {
      version = "1.1.5"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "arch" {
  type = string
}

variable "iso_checksum" {
  type = string
}

variable "iso_url" {
  type = string
}

variable "iso_sets_path" {
  type = string
}

variable "image_name" {
  type = string
}

variable "sets" {
  type = string
}

variable "disk_size" {
  type = string
}

variable "firmware" {
  type = string
}

variable "accelerator" {
  type = string
}

variable "efi_code" {
  type = string
}

variable "efi_vars" {
  type = string
}

variable "set_dir" {
  type = string
}

locals {
  use_efi = var.firmware == "uefi"
  qemu_binary = {
    amd64 = "qemu-system-x86_64"
    arm64 = "qemu-system-aarch64"
  }
  machine_type = {
    amd64 = "pc"
    arm64 = "virt"
  }
  qemuargs = {
    amd64 = [
      ["-device", "virtio-scsi-pci,id=scsi0"],
      ["-device", "scsi-hd,bus=scsi0.0,drive=drive0,bootindex=0"],
      ["-device", "scsi-cd,bus=scsi0.0,drive=cdrom0,bootindex=1"],
      ["-device", "scsi-cd,bus=scsi0.0,drive=cdrom1,bootindex=2"],
      ["-device", "virtio-rng-pci"],
      ["-no-reboot"],
    ]
    arm64 = [
      ["-cpu", var.accelerator == "tcg" ? "cortex-a72" : "host"],
      ["-device", "virtio-gpu-pci"],
      ["-device", "qemu-xhci"], ["-device", "usb-kbd"],
      ["-device", "virtio-scsi-pci,id=scsi0"],
      ["-device", "scsi-hd,bus=scsi0.0,drive=drive0,bootindex=0"],
      ["-device", "scsi-cd,bus=scsi0.0,drive=cdrom0,bootindex=1"],
      ["-device", "scsi-cd,bus=scsi0.0,drive=cdrom1,bootindex=2"],
      ["-device", "virtio-rng-pci"],
      ["-no-reboot"],
    ]
  }
}

source "qemu" "imager" {
  vm_name          = "disk.raw"
  output_directory = "output/images/${var.image_name}"

  iso_checksum    = var.iso_checksum
  iso_url         = var.iso_url
  iso_target_path = "iso/${var.arch}-${basename(var.iso_url)}"

  http_content = {
    "/install.conf" = templatefile("install.conf.pkrtpl", {
      "sets" : var.sets,
      "disk_answer" : local.use_efi ? "G" : "W",
      "iso_sets_path" : var.iso_sets_path,
      "arch" : var.arch,
    })
  }

  cd_files = [for f in fileset(var.set_dir, "*") : "${var.set_dir}/${f}"]
  cd_label = "SITE"

  qemu_binary       = local.qemu_binary[var.arch]
  machine_type      = local.machine_type[var.arch]
  efi_firmware_code = local.use_efi ? var.efi_code : ""
  efi_firmware_vars = local.use_efi ? var.efi_vars : ""
  qemuargs          = local.qemuargs[var.arch]
  accelerator       = var.accelerator
  disk_size         = var.disk_size
  disk_interface    = "virtio-scsi"
  cdrom_interface   = "virtio-scsi"
  cpus              = 2
  headless          = true
  format            = "raw"

  boot_command = [
    "A<enter><wait>",
    "http://{{ .HTTPIP }}:{{ .HTTPPort }}/install.conf<enter>"
  ]
  boot_wait = var.accelerator == "tcg" ? "180s" : "90s"

  # no SSH, no first boot: the install-end reboot is caught by -no-reboot and qemu exits
  communicator     = "none"
  shutdown_timeout = "20m"

  vnc_port_min = 5900
  vnc_port_max = 5900
}

build {
  sources = ["source.qemu.imager"]
}
