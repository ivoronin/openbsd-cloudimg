# openbsd-cloudimg

Packer templates that build sterile OpenBSD cloud images with a built-in minimal cloud-init client.

[![build](https://github.com/ivoronin/openbsd-cloudimg/actions/workflows/build.yml/badge.svg)](https://github.com/ivoronin/openbsd-cloudimg/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/ivoronin/openbsd-cloudimg)](https://github.com/ivoronin/openbsd-cloudimg/releases)

## Table of Contents

[Why this exists](#why-this-exists) · [Overview](#overview) · [Sterility](#sterility) · [Features](#features) · [Build](#build) · [AWS flavor](#aws-flavor) · [Releases](#releases) · [Running locally](#running-locally) · [Configuration](#configuration) · [Requirements](#requirements) · [License](#license)

## Why this exists

Every serious server OS ships an official cloud image. OpenBSD doesn't, even though it's exactly what you'd reach for when a small, audited base and correctness actually matter. Running it in the cloud should be a non-event; instead it's nearly impossible to even get started. This repo closes that gap the practical way: sterile raw images with a built-in cloud-init client, that boot on real cloud hardware and take your SSH key and hostname from instance metadata on first boot.

```bash
# OpenBSD publishes no official cloud image. Build one:
make images VER=7.9 ARCH=amd64 PROFILE=base
```

Out comes a raw `.img`: no root password, no host keys, no authorized_keys, just a pre-created `openbsd` user. On first boot cloud-init drops your SSH key into that account and sets the hostname, from EC2 IMDS or a NoCloud (CIDATA) disk.

## Overview

Packer drives the OpenBSD installer in QEMU through autoinstall(8), unattended, then provisions the image: syspatch to fully patched, the cloud-init client into `rc.local`, and a cleanup pass that wipes all identity before sealing. Output is a raw image.

## Sterility

Nothing static ships. Packer logs into the installer over SSH with a throwaway ed25519 keypair generated on the build host; the private half never enters the image, and root login stays `prohibit-password`. Before sealing, cleanup wipes the public half it installed, along with the rest of the machine's identity:

- `/root/.ssh/authorized_keys` (the install key's public half)
- `/etc/ssh/ssh_host_*` (sshd regenerates these on first boot)
- isakmpd and iked private keys
- `/etc/soii.key`, the SLAAC IPv6 address secret
- the RNG seed (`/etc/random.seed`, `/var/db/host.random`)
- DHCP leases, cached ACPI tables, the ntpd drift file
- build-host traces: `/var/log/*` (truncated), shell history, `/tmp`

Identity arrives at first boot from cloud-init (see [Configuration](#configuration)).

## Features

- Two flavors: `generic` (stock kernel) or `aws` (a custom kernel patched for EC2/Nitro, built in a separate builder VM - see [AWS flavor](#aws-flavor)).
- Two profiles: `base` (minimal, 10G) and `full` (all sets, 40G).
- amd64 (BIOS/MBR or UEFI/GPT firmware) and arm64 (UEFI/GPT only).
- A minimal cloud-init client: ~150 lines of base Perl, nothing from ports.
- Two metadata sources: a NoCloud (CIDATA) disk, then AWS-style IMDS.
- Ships fully patched, with syspatch run at build time.

## Build

One `make images` produces one image:

```bash
make images VER=7.9 ARCH=amd64 PROFILE=base
```

Output lands at `output/images/<name>/<name>.img`, where `<name>` is `openbsd-<ver>-<arch>-<flavor>-<profile>-<firmware>`. `ARCH` and `ACCEL` default to the build host: native acceleration when the target arch matches, `tcg` when it differs. `FIRMWARE` defaults to `bios` on amd64 (legacy/MBR, boots qemu-SeaBIOS and vmd) and `uefi` on arm64 (its only option); pass `FIRMWARE=uefi` for an amd64 cloud image. Note that an amd64 image is either BIOS/MBR or UEFI/GPT, never both - OpenBSD `installboot` sets up one or the other. Add a release by putting its `installNN.iso` SHA256 in `images.json`.

`FLAVOR` selects the kernel: `generic` (stock, the default) or `aws` (a custom EC2/Nitro kernel, see [AWS flavor](#aws-flavor)).

Targets:

- `make images` - build one image (default)
- `make site` - build the site set (the builder stage); a noop unless `FLAVOR=aws`, which `make images FLAVOR=aws` runs automatically
- `make test` - boot the image and check cloud-init injected the key and hostname, for both sources
- `make compress` - xz-compress the image to `.img.xz`
- `make clean` - remove `output/`

Variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `VER` | OpenBSD release | `7.9` |
| `ARCH` | `amd64` or `arm64` | (host arch) |
| `FLAVOR` | `generic` (stock kernel) or `aws` (patched kernel via the builder stage) | `generic` |
| `PROFILE` | `base` (minimal) or `full` (all sets) | `base` |
| `FIRMWARE` | `bios` (MBR, amd64 legacy/vmd) or `uefi` (GPT) | `bios` amd64; `uefi` for arm64 or `aws` |
| `ACCEL` | QEMU accelerator; native (`kvm`/`hvf`) when the target arch matches the host, else `tcg` | (auto) |
| `EFI_CODE` / `EFI_VARS` | UEFI firmware paths for `uefi` builds; auto-located | (auto) |

## AWS flavor

The `aws` flavor runs a two-stage build: a throwaway builder VM applies the patch-set under `flavors/aws/<ver>/`, builds the `AWS.MP` and `AWS` (SP) kernels into a site set, and the imager installs them as `/bsd` and `/bsd.sp`. So a `base` image ships patched kernels with no compiler installed (`make images FLAVOR=aws PROFILE=base`).

The kernel is GENERIC minus GPU/drm (mostly to speed up builds), with EC2/Nitro fixes on top: the `nvme(4)` MQES clamp EBS NVMe needs, a PCIe-bridge patch, and a bundled (still WIP) ENA driver. It's built under a custom config, so `uname` stays honest. The kernel carries the published kernel errata (applied to the source before our patches), so it ships fully patched; but syspatch can't reach a custom-config kernel in place, so a kernel CVE released after the build means a rebuilt image (`generic` gets those via syspatch as usual). KARL is preserved - relink kits for both kernels; boot `/bsd.sp` to dodge an MP-only bug.

## Releases

CI builds the matrix (each pinned release on amd64, `generic` and `aws` flavors, `uefi` and `bios` firmware, `base` profile), tests both metadata sources, and publishes attested images to [Releases](https://github.com/ivoronin/openbsd-cloudimg/releases). Inputs are pinned for reproducibility: installer ISO checksums, the Packer version, and SHA-pinned actions.

```bash
gh release download -R ivoronin/openbsd-cloudimg -p 'openbsd-7.9-amd64-generic-base-uefi-*.img.xz'
gh attestation verify openbsd-7.9-amd64-generic-base-uefi-*.img.xz --repo ivoronin/openbsd-cloudimg
```

Assets are named `openbsd-<ver>-<arch>-<flavor>-<profile>-<firmware>-<gitref>-<timestamp>.img.xz`. The release matrix builds both `generic` and `aws` flavors, each in `uefi` and `bios`.

## Running locally

Boot a built or downloaded image on your own machine. Both paths hand cloud-init a NoCloud (CIDATA) seed, so it injects your key into the `openbsd` user on first boot.

### kvm

```bash
ssh-keygen -t ed25519 -f ./id_openbsd -N ''

# CIDATA seed carrying your public key
cat > meta-data <<EOF
local-hostname: obsd1
public-keys:
  - $(cat id_openbsd.pub)
EOF
xorriso -as mkisofs -V CIDATA -J -r -o cidata.iso meta-data

# raw .img from make images, or unxz a release first
qemu-system-x86_64 -accel kvm -m 1G -nographic \
  -drive file=openbsd-7.9-amd64-generic-base-bios.img,format=raw,if=virtio \
  -nic user,model=virtio,hostfwd=tcp::2222-:22 \
  -cdrom cidata.iso

ssh -i id_openbsd -p 2222 openbsd@localhost
```

### vmd

```bash
ssh-keygen -t ed25519 -f ./id_openbsd -N ''

# CIDATA seed carrying your public key (mkhybrid is in base; -r adds the Rock
# Ridge names cloud-init reads, without it meta-data is mangled to META_DAT)
cat > meta-data <<EOF
local-hostname: obsd1
public-keys:
  - $(cat id_openbsd.pub)
EOF
mkhybrid -o cidata.iso -r -V CIDATA meta-data

# first disk is the image, second the seed; -L gives the VM a local IP
rcctl start vmd
vmctl start obsd1 -m 1G -L \
  -d openbsd-7.9-amd64-generic-base-bios.img \
  -d cidata.iso

ssh -i id_openbsd openbsd@100.64.0.3
```

## Configuration

cloud-init runs from `rc.local`: it installs an SSH key into the `openbsd` account, sets the hostname, and runs any user-data as a script. That account (wheel group, passwordless `doas`) is created at build time. NoCloud is checked first, then IMDS.

NoCloud (CIDATA): attach an ISO9660 disk labeled exactly `CIDATA` with a `meta-data` file:

```yaml
local-hostname: web1
public-keys:
  - ssh-ed25519 AAAA... user@host
```

`meta-data` is all you need. An optional `user-data` file beside it is run on first boot (the shebang is ignored; it always runs under `/bin/sh`).

IMDS: with no CIDATA disk, cloud-init queries `http://169.254.169.254/latest`:

- `meta-data/public-keys/0/openssh-key`
- `meta-data/local-hostname`
- `user-data` (optional; run as a `/bin/sh` script on first boot)

The key goes into `~openbsd/.ssh/authorized_keys` in a managed block, rewritten each boot, leaving your other keys alone; the hostname goes into `/etc/myname` and `/etc/hosts`.

## Requirements

- Build on Linux (KVM) or macOS (hvf), or anywhere QEMU runs with `ACCEL=tcg`. Native acceleration needs the host architecture to match the target.
- Packer 1.15.4+, QEMU, `jq` (reads `images.json`), `xz` (`make compress`).
- arm64 builds: edk2 aarch64 UEFI firmware (`qemu-efi-aarch64` on Debian/Ubuntu, bundled with QEMU on macOS), auto-located.
- `make test`: `xorriso` (Packer builds the CIDATA test ISO with it; `hdiutil` on macOS) and `netcat-openbsd`.

## License

[ISC](LICENSE)
