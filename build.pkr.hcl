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
  image_name = "openbsd-${var.version}-${var.arch}-${var.flavor}"
  # Provisioning stack built from the DISABLE_* flags; compact() drops disabled entries.
  provision_scripts = compact([
    var.disable_syspatch ? "" : "scripts/syspatch.sh",
    var.disable_cloud_init ? "" : "scripts/cloud.sh",
    var.disable_cleanup ? "" : "scripts/cleanup.sh",
  ])
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
  # arm64 on "virt" needs: a CPU model (host passthrough under kvm/hvf, but tcg
  # emulation rejects -cpu host, so a concrete core there); a framebuffer
  # (virtio-gpu) plus a USB keyboard (virt has no PS/2) so the boot_command types
  # over VNC; and EFI mode (efi_firmware_*), which makes Packer skip the x86-only
  # "-boot" that virt rejects.
  qemuargs = {
    amd64 = []
    arm64 = [
      ["-cpu", var.accelerator == "tcg" ? "cortex-a72" : "host"],
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
  output_directory = "output/build/${var.arch}/${var.version}/${var.flavor}"

  iso_checksum = var.iso_checksum
  iso_url      = "https://cdn.openbsd.org/pub/OpenBSD/${var.version}/${var.arch}/install${local.tag}.iso"
  # Keep the installer ISO in a predictable iso/ dir (reused across base/full and
  # across runs when the checksum matches) instead of Packer's hash-named cache.
  iso_target_path = "iso/openbsd-${var.version}-${var.arch}.iso"

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
  # tcg emulation reaches the loader prompt far slower than native kvm/hvf, so
  # double the wait before boot_command starts typing.
  boot_wait        = var.accelerator == "tcg" ? "60s" : "30s"
  shutdown_command = "halt -p"

  ssh_private_key_file = data.sshkey.install.private_key_path
  ssh_username         = "root"
  ssh_timeout          = "15m"

  vnc_port_min = 5900
  vnc_port_max = 5900
}

build {
  sources = ["source.qemu.install"]

  # only/except are evaluated in the var/local eval context (Packer decodes them
  # with gohcl against ectx), so except-ing the sole source conditionally skips a
  # whole provisioner - Packer's only lever to drop one.
  provisioner "file" {
    source      = "cloud-init.pl"
    destination = "/usr/local/sbin/cloud-init"
    except      = var.disable_cloud_init ? ["qemu.install"] : []
  }
  provisioner "shell" {
    scripts = local.provision_scripts
    except  = length(local.provision_scripts) == 0 ? ["qemu.install"] : []
  }
}
