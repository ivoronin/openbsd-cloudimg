# openbsd-cloudimg

Packer templates that build sterile OpenBSD cloud images with a built-in minimal cloud-init client.

[![build](https://github.com/ivoronin/openbsd-cloudimg/actions/workflows/build.yml/badge.svg)](https://github.com/ivoronin/openbsd-cloudimg/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/ivoronin/openbsd-cloudimg)](https://github.com/ivoronin/openbsd-cloudimg/releases)

## Table of Contents

[Overview](#overview) · [Sterility](#sterility) · [Features](#features) · [Build](#build) · [Releases](#releases) · [Configuration](#configuration) · [Requirements](#requirements) · [License](#license)

```bash
# OpenBSD publishes no official cloud image. Build one:
make build VER=7.9 ARCH=amd64 FLAVOR=base
```

Out comes a raw `.img`: no root password, no host keys, no authorized_keys, just a pre-created `openbsd` user. On first boot cloud-init drops your SSH key into that account and sets the hostname, from EC2 IMDS or a NoCloud (CIDATA) disk.

## Overview

Packer drives the OpenBSD installer in QEMU through autoinstall(8), unattended, then provisions the image: syspatch to fully patched, the cloud-init client into `rc.local`, and a cleanup pass that wipes all identity before sealing. Output is a raw image.

## Sterility

Nothing static ships. Install authenticates with a per-build ephemeral ed25519 key and `prohibit-password` root, so there is no password or stored key to leak. Before sealing, cleanup wipes:

- `/root/.ssh/authorized_keys`
- `/etc/ssh/ssh_host_*` (sshd regenerates these on first boot)
- isakmpd and iked private keys
- `/etc/soii.key`, the SLAAC IPv6 address secret
- `/var/db/dhcpleased/*`, `/var/db/acpi/*`

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

Output lands at `output/build/<arch>/<version>/<flavor>/openbsd-<ver>-<arch>-<flavor>.img`. Without KVM pass `ACCEL=tcg`, or `ACCEL=hvf` on macOS. Add a release by putting its `installNN.iso` SHA256 in `images.json`.

Targets:

- `make build` - build one image (default)
- `make smoke` - boot the image and check cloud-init injected the key and hostname, for both sources (or one, via `CLOUD_INIT_SOURCE`)
- `make compress` - gzip the image to `.img.gz`
- `make clean` - remove `output/`

Variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `VER` | OpenBSD release | `7.9` |
| `ARCH` | `amd64` or `arm64` | `amd64` |
| `FLAVOR` | `base` (minimal) or `full` (all sets) | `base` |
| `ACCEL` | QEMU accelerator: `kvm`, `tcg`, `hvf` or `none` | `kvm` |
| `ISO_CHECKSUM` | Installer ISO SHA256; read from `images.json` when unset | (from `images.json`) |
| `CLOUD_INIT_SOURCE` | `make smoke` only: limit to `imds` or `cidata` | (both) |
| `EFI_CODE` / `EFI_VARS` | arm64 UEFI firmware paths; auto-located | (auto) |
| `DISABLE_SYSPATCH` | `1` skips syspatch (debug) | (unset) |
| `DISABLE_CLOUD_INIT` | `1` skips the cloud-init install (debug) | (unset) |
| `DISABLE_CLEANUP` | `1` skips the identity wipe (debug) | (unset) |

## Releases

CI builds the full matrix (release × arch × flavor), smoke-tests both metadata sources, and publishes attested images to [Releases](https://github.com/ivoronin/openbsd-cloudimg/releases). Inputs are pinned for reproducibility: installer ISO checksums, the Packer version, a frozen apt snapshot, and SHA-pinned actions.

```bash
gh release download -R ivoronin/openbsd-cloudimg -p 'openbsd-7.9-amd64-base-*.img.gz'
gh attestation verify openbsd-7.9-amd64-base-*.img.gz --repo ivoronin/openbsd-cloudimg
```

Assets are named `openbsd-<ver>-<arch>-<flavor>-<gitref>-<timestamp>.img.gz`.

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
