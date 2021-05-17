build {
  source "source.qemu.install" {
    output_directory = "output-aws"
  }
  provisioner "file" {
    source = "scripts/cloud-init.sh"
    destination = "/usr/local/sbin/cloud-init"
  }
  provisioner "shell" {
    scripts = [
      "scripts/syspatch.sh",
      "scripts/console.sh",
      "scripts/aws.sh",
      "scripts/cleanup.sh",
    ]
  }
  post-processors {
    post-processor "shell-local" {
      script = "scripts/import-aws.sh"
      environment_vars = [
        "IMAGE_NAME=${local.image_name}",
        "BUCKET_NAME=openbsd-cloudimg",
      ]
    }
  }
}
