# OpenBSD Cloud Images
Packer templates for building OpenBSD cloud machine images

## Cloud services support
 - Google Cloud Platform (GCP): good compatibility and integration
 - Amazon Web Services (AWS):
    - Older Xen-based instances - good compatiblity, basic cloud-init-like integration
    - Newer KVM-based "Nitro" instances - not supported, won't boot. Kernel can't access root device because of NVMe driver issues, no driver for Elastic Network Adapter (ENA). AMD instances (t3a, c5a, m5a, ...) wont boot at all, check https://www.mail-archive.com/misc@openbsd.org/msg178332.html
 - Microsoft Azure: TBD

## Software requirements
  - QEMU/KVM host
  - Packer 1.7 or later
  - jq
  - aws
  
## Required permissions
### Google Compute Platform
  - Compute Instance Admin (v1) 
  - Storage Object Admin (for intermediate bucket)
### Amazon Web Services
  - ec2:ImportSnapshot
  - ec2:DescribeImportSnapshotTasks
  - ec2:RegisterImage
  - s3:GetBucketLocation (for intermediate bucket)
  - s3:PutObject (for intermediate bucket)
  - s3:DeleteObject (for intermediate bucket)

## Running
Customize Packer templates and scripts to match your environment (bucket names, project ids and so on), set required environment variables (`AWS_SECRET_ACCESS_KEY`, `AWS_ACCESS_KEY_ID`, `GOOGLE_APPLICATION_CREDENTIALS`) and run:
```sh
packer build .
```
