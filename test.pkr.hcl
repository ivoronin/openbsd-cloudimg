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

variable "image" {
  type        = string
  description = "Path to the built raw .img to smoke-test"
}

variable "accelerator" {
  type    = string
  default = "kvm"
}

variable "arch" {
  type    = string
  default = "amd64"
}

variable "efi_code" {
  type    = string
  default = ""
}

variable "efi_vars" {
  type    = string
  default = ""
}

data "sshkey" "test" {
  type = "ed25519"
}

locals {
  qemu_binary = {
    amd64 = "qemu-system-x86_64"
    arm64 = "qemu-system-aarch64"
  }
  machine_type = {
    amd64 = "pc"
    arm64 = "virt"
  }
  # Fakes an EC2 IMDS at 169.254.169.254 for the image's cloud-init. Three SLIRP
  # constraints: (1) a guestfwd guest address must be inside the guest network,
  # hence the link-local 169.254.0.0/16; (2) the forward target is a host-side
  # connect, so it points at Packer's HTTP server on 127.0.0.1, not {{ .HTTPIP }}
  # (the guest gateway, unreachable from the host); (3) it uses "-cmd:nc" not
  # "-tcp:" because SLIRP does not forward a write-callback guestfwd's host close
  # to the guest, which hangs OpenBSD ftp; nc relays the close. hostfwd reaches
  # sshd regardless of the guest's address.
  net_qemuargs = [
    ["-netdev", "user,id=n0,net=169.254.0.0/16,host=169.254.0.2,dhcpstart=169.254.0.15,hostfwd=tcp::{{ .SSHHostPort }}-:22,guestfwd=tcp:169.254.169.254:80-cmd:nc 127.0.0.1 {{ .HTTPPort }}"],
    ["-device", "virtio-net,netdev=n0"],
  ]
  # arm64 "virt" has no default display or PS/2 keyboard; add a virtio-gpu frame-
  # buffer and a USB keyboard so Packer's VNC connection works and a human can
  # watch/type at the console while debugging. amd64 needs neither.
  arch_qemuargs = {
    amd64 = []
    arm64 = [["-cpu", "host"], ["-device", "virtio-gpu-pci"], ["-device", "qemu-xhci"], ["-device", "usb-kbd"]]
  }
}

# Boot the built image on a disposable clone (the source .img is never written)
# and let it reach a fake EC2 IMDS. cloud-init in the image fetches the ssh key
# and hostname from http://169.254.169.254/latest/...; Packer's own HTTP server
# holds those responses and qemuargs guestfwd redirects the guest's IMDS
# requests to it. So logging in at all proves the image boots and cloud-init +
# IMDS work - there is no other way into the cleaned image.
source "qemu" "smoke" {
  vm_name          = "smoke-test"
  output_directory = "output/smoke"

  disk_image       = true
  iso_url          = var.image
  iso_checksum     = "none"
  skip_resize_disk = true
  disk_interface   = "virtio"
  format           = "raw"

  qemu_binary       = local.qemu_binary[var.arch]
  machine_type      = local.machine_type[var.arch]
  efi_firmware_code = var.arch == "arm64" ? var.efi_code : ""
  efi_firmware_vars = var.arch == "arm64" ? var.efi_vars : ""
  accelerator       = var.accelerator
  headless          = true

  http_content = {
    "/latest/meta-data/public-keys/0/openssh-key" = data.sshkey.test.public_key
    "/latest/meta-data/local-hostname"            = "smoke-test"
  }

  qemuargs = concat(local.arch_qemuargs[var.arch], local.net_qemuargs)

  ssh_username         = "openbsd"
  ssh_private_key_file = data.sshkey.test.private_key_path
  ssh_timeout          = "10m"
  shutdown_command     = "doas halt -p"

  vnc_port_min = 5900
  vnc_port_max = 5900
}

build {
  sources = ["source.qemu.smoke"]

  provisioner "shell" {
    scripts = ["test/checks.sh"]
  }
}
