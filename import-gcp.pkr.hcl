build {
  source "source.qemu.install" {
    output_directory = "output-gcp"
  }
  provisioner "shell" {
    scripts = [
      "scripts/syspatch.sh",
      "scripts/console.sh",
      "scripts/gce.sh",
      "scripts/cleanup.sh",
    ]
  }
  post-processors {
    post-processor "compress" {
      output = "output-gcp/openbsd.raw.tar.gz"
    }
    post-processor "googlecompute-import" {
      image_name   = local.image_name
      bucket       = "openbsd-cloudimg"
      project_id   = "openbsd-cloudimg"
      image_family = "openbsd"
    }
  }
}
