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

variable "efi_code" {
  type        = string
  description = "UEFI firmware CODE (arm64 only, e.g. edk2-aarch64-code.fd)"
  default     = ""
}

variable "efi_vars" {
  type        = string
  description = "UEFI firmware VARS template (arm64 only, e.g. edk2-arm-vars.fd)"
  default     = ""
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
  qemu_binary = {
    amd64 = "qemu-system-x86_64"
    arm64 = "qemu-system-aarch64"
  }
  machine_type = {
    amd64 = "pc"
    arm64 = "virt"
  }
  # arm64 on "virt" needs: the host CPU model; a framebuffer (virtio-gpu) plus a
  # USB keyboard (virt has no PS/2) so the boot_command types over VNC; and EFI
  # mode (efi_firmware_*), which makes Packer skip the x86-only "-boot" that virt
  # rejects.
  qemuargs = {
    amd64 = []
    arm64 = [
      ["-cpu", "host"],
      ["-device", "virtio-gpu-pci"],
      ["-device", "qemu-xhci"], ["-device", "usb-kbd"],
      # disk_interface and cdrom_interface=virtio-scsi make Packer build BOTH the
      # target disk (drive id drive0, OpenBSD sd0) and the install ISO (cdrom0, cd0)
      # as -drive entries we never touch - so no path is hardcoded. We override only
      # -device: one shared controller wiring the disk at bootindex=0 and the CD at
      # bootindex=1, so the first boot falls through the empty disk to the CD
      # installer and the installed disk boots first on the post-install reboot.
      ["-device", "virtio-scsi-pci,id=scsi0"],
      ["-device", "scsi-hd,bus=scsi0.0,drive=drive0,bootindex=0"],
      ["-device", "scsi-cd,bus=scsi0.0,drive=cdrom0,bootindex=1"],
    ]
  }
}

source "qemu" "install" {
  vm_name          = "${local.image_name}.img"
  output_directory = "output/${var.flavor}"

  iso_checksum = var.iso_checksum
  iso_url      = "https://cdn.openbsd.org/pub/OpenBSD/${var.version}/${var.arch}/install${local.tag}.iso"

  http_content = {
    "/install.conf" = templatefile("install.conf.pkrtpl", {
      "ssh_public_key" : data.sshkey.install.public_key,
      "sets" : local.sets[var.flavor]
    })
  }

  qemu_binary       = local.qemu_binary[var.arch]
  machine_type      = local.machine_type[var.arch]
  efi_firmware_code = var.arch == "arm64" ? var.efi_code : ""
  efi_firmware_vars = var.arch == "arm64" ? var.efi_vars : ""
  qemuargs          = local.qemuargs[var.arch]
  accelerator       = var.accelerator
  disk_size         = local.disk_size[var.flavor]
  disk_interface    = var.arch == "arm64" ? "virtio-scsi" : "virtio"
  cdrom_interface   = var.arch == "arm64" ? "virtio-scsi" : ""
  cpus              = 1
  headless          = true
  format            = "raw"

  boot_command = [
    "A<enter><wait>",
    "http://{{ .HTTPIP }}:{{ .HTTPPort }}/install.conf<enter>"
  ]
  boot_wait        = "30s"
  shutdown_command = "halt -p"

  ssh_private_key_file = data.sshkey.install.private_key_path
  ssh_username         = "root"
  ssh_timeout          = "15m"

  vnc_port_min = 5900
  vnc_port_max = 5900
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
