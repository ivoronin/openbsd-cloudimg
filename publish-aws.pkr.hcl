packer {
  required_plugins {
    ebsdirect = {
      version = "0.1.0"
      source  = "github.com/ivoronin/ebsdirect"
    }
  }
}

variable "image" {
  type        = string
  description = "Path to the raw disk.raw to register as an AMI (size a whole number of GiB)."
}

variable "image_name" {
  type        = string
  description = "Name for the registered AMI."
}

variable "boot_mode" {
  type        = string
  description = "legacy-bios, uefi, or uefi-preferred."
}

variable "architecture" {
  type        = string
  description = "x86_64 or arm64."
}

source "null" "aws" {
  communicator = "none"
}

build {
  sources = ["source.null.aws"]

  post-processors {
    # Register the already-built image instead of a fresh builder artifact.
    post-processor "artifice" {
      files = [var.image]
    }

    # Write the raw image straight into an EBS snapshot via the EBS direct APIs and
    # register it as an AMI - no S3 bucket, no vmimport role, and no VM Import OS
    # validation (which rejects OpenBSD's layout). Region and creds come from the
    # AWS SDK config.
    post-processor "ebsdirect" {
      ami_name     = var.image_name
      boot_mode    = var.boot_mode
      architecture = var.architecture
    }
  }
}
