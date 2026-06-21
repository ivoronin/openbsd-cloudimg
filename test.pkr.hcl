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

data "sshkey" "test" {
  type = "ed25519"
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

  accelerator = var.accelerator
  headless    = true

  http_content = {
    "/latest/meta-data/public-keys/0/openssh-key" = data.sshkey.test.public_key
    "/latest/meta-data/local-hostname"            = "smoke-test"
  }

  # Two SLIRP quirks: (1) a guestfwd's guest address must sit inside the guest
  # network, so move the network into link-local 169.254.0.0/16 to host the
  # fixed IMDS address 169.254.169.254; (2) the guestfwd target is a host-side
  # connect, so it must point at Packer's HTTP server on the host loopback,
  # NOT {{ .HTTPIP }} - that resolves to the guest-facing gateway 10.0.2.2,
  # which the host cannot connect to (qemu then exits at boot). hostfwd reaches
  # sshd regardless of the guest's address.
  qemuargs = [
    ["-netdev", "user,id=n0,net=169.254.0.0/16,host=169.254.0.2,dhcpstart=169.254.0.15,hostfwd=tcp::{{ .SSHHostPort }}-:22,guestfwd=tcp:169.254.169.254:80-tcp:127.0.0.1:{{ .HTTPPort }}"],
    ["-device", "virtio-net,netdev=n0"],
  ]

  ssh_username         = "openbsd"
  ssh_private_key_file = data.sshkey.test.private_key_path
  ssh_timeout          = "10m"
  shutdown_command     = "doas halt -p"
}

build {
  sources = ["source.qemu.smoke"]

  provisioner "shell" {
    scripts = ["test/checks.sh"]
  }
}
