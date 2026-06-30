packer {
  required_plugins {
    googlecompute = {
      version = "1.2.6"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "image" {
  type        = string
  description = "Path to the gzip tar to import (the make compress output); it must hold a single disk.raw."
}

variable "image_name" {
  type        = string
  description = "Name for the created GCE image (lowercase, no dots)."
}

variable "project" {
  type        = string
  description = "GCP project id."
}

variable "bucket" {
  type        = string
  description = "Existing GCS bucket the tarball is staged in."
}

source "null" "gce" {
  communicator = "none"
}

build {
  sources = ["source.null.gce"]

  post-processors {
    # Import the prebuilt tarball (the make compress output) directly - it already
    # holds a single disk.raw, which is what GCE's import wants. No re-tarring.
    post-processor "artifice" {
      files = [var.image]
    }

    # Upload to GCS and create the GCE image. Authenticates via Application
    # Default Credentials (GOOGLE_APPLICATION_CREDENTIALS / gcloud ADC).
    post-processor "googlecompute-import" {
      project_id = var.project
      bucket     = var.bucket
      image_name = var.image_name
    }
  }
}
