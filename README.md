# openbsd-cloudimg

Packer templates that build sterile OpenBSD cloud images with a built-in minimal cloud-init client.

[![build](https://github.com/ivoronin/openbsd-cloudimg/actions/workflows/build.yml/badge.svg)](https://github.com/ivoronin/openbsd-cloudimg/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/ivoronin/openbsd-cloudimg)](https://github.com/ivoronin/openbsd-cloudimg/releases)

## Table of Contents

[Overview](#overview) · [Sterility](#sterility) · [Features](#features) · [Build](#build) · [Releases](#releases) · [Running locally](#running-locally) · [Configuration](#configuration) · [Requirements](#requirements) · [License](#license)

```bash
# OpenBSD publishes no official cloud image. Build one:
make build VER=7.9 ARCH=amd64 FLAVOR=base
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

- Two flavors: `base` (minimal, 10G) and `full` (all sets, 40G).
- amd64 and arm64 (arm64 builds under UEFI).
- A minimal cloud-init client: ~120 lines of base Perl, nothing from ports.
- Two metadata sources: a NoCloud (CIDATA) disk, then AWS-style IMDS.
- Ships fully patched, with syspatch run at build time.

## Build

One `make build` produces one image:

```bash
make build VER=7.9 ARCH=amd64 FLAVOR=base
```

Output lands at `output/build/<arch>/<version>/<flavor>/openbsd-<ver>-<arch>-<flavor>.img`. `ARCH` and `ACCEL` default to the build host: native acceleration when the target arch matches, `tcg` when it differs. Override either as needed. Add a release by putting its `installNN.iso` SHA256 in `images.json`.

Targets:

- `make build` - build one image (default)
- `make smoke` - boot the image and check cloud-init injected the key and hostname, for both sources (or one, via `CLOUD_INIT_SOURCE`)
- `make compress` - gzip the image to `.img.gz`
- `make clean` - remove `output/`

Variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `VER` | OpenBSD release | `7.9` |
| `ARCH` | `amd64` or `arm64` | (host arch) |
| `FLAVOR` | `base` (minimal) or `full` (all sets) | `base` |
| `ACCEL` | QEMU accelerator; native (`kvm`/`hvf`) when the target arch matches the host, else `tcg` | (auto) |
| `ISO_CHECKSUM` | Installer ISO SHA256; read from `images.json` when unset | (from `images.json`) |
| `CLOUD_INIT_SOURCE` | `make smoke` only: limit to `imds` or `cidata` | (both) |
| `EFI_CODE` / `EFI_VARS` | arm64 UEFI firmware paths; auto-located | (auto) |
| `DISABLE_SYSPATCH` | `1` skips syspatch (debug) | (unset) |
| `DISABLE_CLOUD_INIT` | `1` skips the cloud-init install (debug) | (unset) |
| `DISABLE_CLEANUP` | `1` skips the identity wipe (debug) | (unset) |

## Releases

CI builds the full matrix (release × arch × flavor), smoke-tests both metadata sources, and publishes attested images to [Releases](https://github.com/ivoronin/openbsd-cloudimg/releases). Inputs are pinned for reproducibility: installer ISO checksums, the Packer version, and SHA-pinned actions.

```bash
gh release download -R ivoronin/openbsd-cloudimg -p 'openbsd-7.9-amd64-base-*.img.gz'
gh attestation verify openbsd-7.9-amd64-base-*.img.gz --repo ivoronin/openbsd-cloudimg
```

Assets are named `openbsd-<ver>-<arch>-<flavor>-<gitref>-<timestamp>.img.gz`.

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

# raw .img from make build, or gunzip a release first
qemu-system-x86_64 -accel kvm -m 1G -nographic \
  -drive file=openbsd-7.9-amd64-base.img,format=raw,if=virtio \
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
  -d openbsd-7.9-amd64-base.img \
  -d cidata.iso

ssh -i id_openbsd openbsd@100.64.0.3
```

## Configuration

cloud-init runs from `rc.local`: it installs an SSH key into the `openbsd` account and sets the hostname. That account (wheel group, passwordless `doas`) is created at build time. NoCloud is checked first, then IMDS.

NoCloud (CIDATA): attach an ISO9660 disk labeled exactly `CIDATA` with a `meta-data` file:

```yaml
local-hostname: web1
public-keys:
  - ssh-ed25519 AAAA... user@host
```

Only `meta-data` is read; no `user-data` needed.

IMDS: with no CIDATA disk, cloud-init queries `http://169.254.169.254/latest`:

- `meta-data/public-keys/0/openssh-key`
- `meta-data/local-hostname`

The key goes into `~openbsd/.ssh/authorized_keys` in a managed block, rewritten each boot, leaving your other keys alone; the hostname goes into `/etc/myname` and `/etc/hosts`. Build with `DISABLE_CLOUD_INIT=1` to omit all of it.

## Requirements

- Build on Linux (KVM) or macOS (hvf), or anywhere QEMU runs with `ACCEL=tcg`. Native acceleration needs the host architecture to match the target.
- Packer 1.15.4+, QEMU, `jq` (reads `images.json`), `pigz` (`make compress`).
- arm64 builds: edk2 aarch64 UEFI firmware (`qemu-efi-aarch64` on Debian/Ubuntu, bundled with QEMU on macOS), auto-located.
- `make smoke`: `xorriso` (Packer builds the CIDATA test ISO with it; `hdiutil` on macOS) and `netcat-openbsd`.

## License

[ISC](LICENSE)
