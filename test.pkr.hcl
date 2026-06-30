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
  type = string
}

variable "image_name" {
  type = string
}

variable "accelerator" {
  type = string
}

variable "arch" {
  type = string
}

variable "firmware" {
  type = string
}

variable "efi_code" {
  type = string
}

variable "efi_vars" {
  type = string
}

variable "cloud_tini_source" {
  type = string
}

data "sshkey" "test" {
  type = "ed25519"
}

locals {
  use_efi   = var.firmware == "uefi"
  user_data = "#!/bin/sh\necho ${var.cloud_tini_source} > /tmp/cloud-tini-user-data-source\n"
  qemu_binary = {
    amd64 = "qemu-system-x86_64"
    arm64 = "qemu-system-aarch64"
  }
  machine_type = {
    amd64 = "pc"
    arm64 = "virt"
  }
  # imds/gce: SLIRP-faked metadata server - guestfwd 169.254.169.254:80 to
  # Packer's HTTP server via "-cmd:nc" (SLIRP does not forward a write-callback
  # guestfwd's host close, which hangs OpenBSD ftp; nc relays it). cidata: SSH
  # only, no metadata server, so a login proves the disk path. hostfwd reaches
  # sshd in all three.
  netdev = var.cloud_tini_source != "cidata" ? "user,id=n0,net=169.254.0.0/16,host=169.254.0.2,dhcpstart=169.254.0.15,hostfwd=tcp::{{ .SSHHostPort }}-:22,guestfwd=tcp:169.254.169.254:80-cmd:nc 127.0.0.1 {{ .HTTPPort }}" : "user,id=n0,hostfwd=tcp::{{ .SSHHostPort }}-:22"
  net_qemuargs = [
    ["-netdev", local.netdev],
    ["-device", "virtio-net,netdev=n0"],
  ]
  serial_qemuargs = [
    ["-serial", "file:{{ .OutputDir }}/console.log"],
  ]
  # arm64 "virt" needs a CPU model (host passthrough under kvm/hvf, but tcg
  # emulation rejects -cpu host, so a concrete core there). It also has no default
  # display or PS/2 keyboard; add a virtio-gpu framebuffer and a USB keyboard so
  # Packer's VNC connection works and a human can watch/type at the console while
  # debugging. amd64 needs neither.
  arch_qemuargs = {
    amd64 = []
    arm64 = [["-cpu", var.accelerator == "tcg" ? "cortex-a72" : "host"], ["-device", "virtio-gpu-pci"], ["-device", "qemu-xhci"], ["-device", "usb-kbd"]]
  }
  # Fake metadata served over the guestfwd above. imds: AWS schema - the probe
  # needs instance-id, and the two-key index exercises multi-key enumeration
  # (login needs only key 0; key 1 is the same key with a different comment).
  # gce: GCE schema - ssh-keys are "username:<key>" and the username is stripped.
  # cidata serves from cd_content instead, so its map is empty.
  imds_http = {
    "/latest/meta-data/instance-id"               = "i-test0000"
    "/latest/meta-data/public-keys/"              = "0=tester\n1=tester"
    "/latest/meta-data/public-keys/0/openssh-key" = data.sshkey.test.public_key
    "/latest/meta-data/public-keys/1/openssh-key" = "${data.sshkey.test.public_key} key2"
    "/latest/meta-data/local-hostname"            = "tester"
    "/latest/user-data"                           = local.user_data
  }
  gce_http = {
    "/computeMetadata/v1/instance/id"                   = "1234567890"
    "/computeMetadata/v1/instance/attributes/ssh-keys"  = "openbsd:${data.sshkey.test.public_key}"
    "/computeMetadata/v1/instance/hostname"             = "tester"
    "/computeMetadata/v1/instance/attributes/user-data" = local.user_data
  }
}

# Boot the built image on a disposable clone (the source .img is never written)
# and let it reach a fake EC2 IMDS. cloud-tini in the image fetches the ssh key
# and hostname from http://169.254.169.254/latest/...; Packer's own HTTP server
# holds those responses and qemuargs guestfwd redirects the guest's IMDS
# requests to it. So logging in at all proves the image boots and cloud-tini +
# IMDS work - there is no other way into the cleaned image.
source "qemu" "tester" {
  vm_name          = "tester"
  output_directory = "output/tests/${var.image_name}/${var.cloud_tini_source}"

  disk_image       = true
  iso_url          = var.image
  iso_checksum     = "none"
  skip_resize_disk = true
  disk_interface   = "virtio"
  format           = "raw"

  qemu_binary       = local.qemu_binary[var.arch]
  machine_type      = local.machine_type[var.arch]
  efi_firmware_code = local.use_efi ? var.efi_code : ""
  efi_firmware_vars = local.use_efi ? var.efi_vars : ""
  accelerator       = var.accelerator
  cpus              = 2
  headless          = true

  http_content = var.cloud_tini_source == "imds" ? local.imds_http : var.cloud_tini_source == "gce" ? local.gce_http : {}

  # cidata: Packer builds a CIDATA-labeled ISO9660 from this content and attaches
  # it; the ephemeral key is the sshkey data source Packer already holds. The
  # meta-data is exactly the block-YAML shape cloud-tini's parser expects.
  cd_label = var.cloud_tini_source == "cidata" ? "CIDATA" : null
  cd_content = var.cloud_tini_source == "cidata" ? {
    "meta-data" = "local-hostname: tester\npublic-keys:\n  - ${data.sshkey.test.public_key}\n"
    "user-data" = local.user_data
  } : null

  qemuargs = concat(local.arch_qemuargs[var.arch], local.serial_qemuargs, local.net_qemuargs)

  ssh_username         = "openbsd"
  ssh_private_key_file = data.sshkey.test.private_key_path
  ssh_timeout          = "10m"
  shutdown_command     = "doas halt -p"

  vnc_port_min = 5900
  vnc_port_max = 5900
}

build {
  sources = ["source.qemu.tester"]

  provisioner "shell" {
    # Login already proves boot, cloud-tini, and ssh-key injection; assert that
    # cloud-tini also applied the IMDS-provided local-hostname.
    inline = [<<-EOT
      relink_dir=/usr/share/relink/kernel/AWS.MP
      relink_log=$relink_dir/relink.log
      if doas /bin/test -d "$relink_dir"; then
        relink_wait=0
        while ! doas /bin/test -f "$relink_log" && [ "$relink_wait" -lt 120 ]; do
          sleep 1
          relink_wait=$((relink_wait + 1))
        done
      fi
      if doas /bin/test -f "$relink_log"; then
        echo "=== $relink_log ==="
        doas cat "$relink_log"
      fi
      if [ "$(hostname)" != tester ]; then
        echo "hostname is '$(hostname)', expected tester" >&2
        exit 1
      fi
      if [ "$(cat /tmp/cloud-tini-user-data-source)" != "${var.cloud_tini_source}" ]; then
        echo "user-data did not run for ${var.cloud_tini_source}" >&2
        exit 1
      fi
      echo "test checks passed"
    EOT
    ]
  }
}
