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

variable "firmware" {
  type        = string
  description = "Boot firmware: uefi (GPT) or bios (MBR, amd64 only). arm64 is always uefi."
  default     = "uefi"
}

variable "build" {
  type        = string
  description = "Build target: generic (stock kernel) or aws (patched kernel)"
  default     = "generic"
}

variable "accelerator" {
  type        = string
  description = "QEMU accelerator: kvm (CI), tcg, hvf or none"
  default     = "kvm"
}

variable "efi_code" {
  type        = string
  description = "UEFI firmware CODE for uefi builds (edk2-aarch64-code.fd / edk2-x86_64-code.fd)"
  default     = ""
}

variable "efi_vars" {
  type        = string
  description = "UEFI firmware VARS template for uefi builds (edk2-arm-vars.fd / edk2-i386-vars.fd)"
  default     = ""
}

variable "set_dir" {
  type        = string
  description = "Host dir with the site set + SHA256, ridden as cd1 (aws-style targets; empty for generic)"
  default     = ""
}

variable "disable_syspatch" {
  type        = bool
  description = "Skip the syspatch provisioning step (debug builds)"
  default     = false
}

variable "disable_cloud_init" {
  type        = bool
  description = "Skip cloud-init setup - its file upload and cloud.sh (debug builds)"
  default     = false
}

variable "disable_cleanup" {
  type        = bool
  description = "Skip the cleanup provisioning step (debug builds)"
  default     = false
}

data "sshkey" "install" {
  type = "ed25519"
}

locals {
  tag        = replace(var.version, ".", "")
  image_name = "openbsd-${var.version}-${var.arch}-${var.build}-${var.flavor}-${var.firmware}"
  # arm64 is UEFI-only; on amd64, uefi means GPT and bios means MBR (installboot picks one).
  use_efi = var.arch == "arm64" || var.firmware == "uefi"
  provision_scripts = compact([
    var.disable_syspatch ? "" : "scripts/syspatch.sh",
    var.disable_cloud_init ? "" : "scripts/cloud.sh",
    var.disable_cleanup ? "" : "scripts/cleanup.sh",
  ])
  # The site set rides cd1 only for non-generic targets.
  has_site = var.build != "generic"
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
  # arm64 "virt" needs a concrete CPU under tcg, a framebuffer + USB keyboard for the
  # VNC boot_command, and EFI mode.
  qemuargs = {
    # amd64 uefi: serve disk + install media over virtio-scsi so OVMF's fast virtio Block
    # I/O loads bsd.rd in seconds - its IDE/ATAPI path is PIO-slow (~80s for the ramdisk).
    # bios keeps the default IDE CD (SeaBIOS reads it fine).
    amd64 = local.use_efi ? concat([
      ["-device", "virtio-scsi-pci,id=scsi0"],
      ["-device", "scsi-hd,bus=scsi0.0,drive=drive0,bootindex=0"],
      ["-device", "scsi-cd,bus=scsi0.0,drive=cdrom0,bootindex=1"],
    ], local.has_site ? [["-device", "scsi-cd,bus=scsi0.0,drive=cdrom1,bootindex=2"]] : []) : []
    arm64 = concat([
      ["-cpu", var.accelerator == "tcg" ? "cortex-a72" : "host"],
      ["-device", "virtio-gpu-pci"],
      ["-device", "qemu-xhci"], ["-device", "usb-kbd"],
      # Disk at bootindex=0, installer CD at bootindex=1: the empty disk falls through
      # to the CD installer, then boots first after install.
      ["-device", "virtio-scsi-pci,id=scsi0"],
      ["-device", "scsi-hd,bus=scsi0.0,drive=drive0,bootindex=0"],
      ["-device", "scsi-cd,bus=scsi0.0,drive=cdrom0,bootindex=1"],
      # cd1 (site set) on aws targets only; on virt we must -device it.
    ], local.has_site ? [["-device", "scsi-cd,bus=scsi0.0,drive=cdrom1,bootindex=2"]] : [])
  }
}

source "qemu" "image" {
  vm_name          = "${local.image_name}.img"
  output_directory = "output/build/${var.arch}/${var.version}/${var.build}/${var.flavor}/${var.firmware}"

  iso_checksum = var.iso_checksum
  iso_url      = "https://cdn.openbsd.org/pub/OpenBSD/${var.version}/${var.arch}/install${local.tag}.iso"
  # Predictable iso/ path, reused across runs, instead of Packer's hash-named cache.
  iso_target_path = "iso/openbsd-${var.version}-${var.arch}.iso"

  http_content = {
    "/install.conf" = templatefile("install.conf.pkrtpl", {
      "ssh_public_key" : data.sshkey.install.public_key,
      "sets" : local.sets[var.flavor],
      "disk_answer" : local.use_efi ? "G" : "W",
      "version" : var.version,
      "arch" : var.arch,
      "site" : local.has_site
    })
  }

  # Round-2 sets ride cd1 (aws targets only; empty = no cd1).
  cd_files = local.has_site ? ["${var.set_dir}/site${local.tag}.tgz", "${var.set_dir}/SHA256"] : []
  cd_label = "SITE"

  qemu_binary       = local.qemu_binary[var.arch]
  machine_type      = local.machine_type[var.arch]
  efi_firmware_code = local.use_efi ? var.efi_code : ""
  efi_firmware_vars = local.use_efi ? var.efi_vars : ""
  qemuargs          = local.qemuargs[var.arch]
  accelerator       = var.accelerator
  disk_size         = local.disk_size[var.flavor]
  disk_interface    = local.use_efi ? "virtio-scsi" : "virtio"
  cdrom_interface   = local.use_efi ? "virtio-scsi" : ""
  cpus              = 1
  headless          = true
  format            = "raw"

  boot_command = [
    "A<enter><wait>",
    "http://{{ .HTTPIP }}:{{ .HTTPPort }}/install.conf<enter>"
  ]
  # uefi via virtio-scsi boots ~as fast as bios; a little extra for OVMF init.
  boot_wait        = local.use_efi ? (var.accelerator == "tcg" ? "120s" : "60s") : (var.accelerator == "tcg" ? "60s" : "30s")
  shutdown_command = "halt -p"

  ssh_private_key_file = data.sshkey.install.private_key_path
  ssh_username         = "root"
  ssh_timeout          = "15m"

  vnc_port_min = 5900
  vnc_port_max = 5900
}

build {
  sources = ["source.qemu.image"]

  # cloud-init client; scripts/cloud.sh wires the user, doas and rc.local.
  provisioner "file" {
    source      = "cloud-init.pl"
    destination = "/usr/local/sbin/cloud-init"
    except      = var.disable_cloud_init ? ["qemu.image"] : []
  }

  # except-ing the sole source is Packer's only way to skip a provisioner conditionally.
  provisioner "shell" {
    scripts = local.provision_scripts
    except  = length(local.provision_scripts) == 0 ? ["qemu.image"] : []
  }
}
