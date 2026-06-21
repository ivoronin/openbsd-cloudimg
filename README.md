# OpenBSD Cloud Images

Packer template that builds OpenBSD cloud images with QEMU, fanned out by GitHub Actions into one job per matrix cell.

## Build

Needs an amd64 Linux host with KVM, Packer 1.15.4+, QEMU, xz and jq.

```
make build VER=7.9 ARCH=amd64 FLAVOR=base
```

Without KVM pass `ACCEL=tcg`. Add an OpenBSD version by putting its `installNN.iso` checksum into `images.json`.
