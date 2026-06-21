# OpenBSD Cloud Images

Packer template that builds OpenBSD cloud images with QEMU, fanned out by GitHub Actions into one job per matrix cell.

The matrix lives in `images.json`: OpenBSD 7.8 and 7.9, amd64, flavors `base` (minimal sets) and `full` (all sets). Each cell produces a compressed `qcow2` and a gzipped `raw`.

## Build

Needs an amd64 Linux host with KVM, Packer 1.15.4+, QEMU and jq.

```
make build VER=7.9 ARCH=amd64 FLAVOR=base
```

Without KVM pass `ACCEL=tcg`. Add a release by putting its `installNN.iso` checksum into `images.json`.
