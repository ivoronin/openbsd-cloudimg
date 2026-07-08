# openbsd-cloudimg

The cloud image OpenBSD doesn't ship: raw OpenBSD images with metadata-provided SSH keys, EC2/Nitro variants with custom kernels and ENA networking, and local QEMU/vmd use.

> [!CAUTION]
> This is an unofficial OpenBSD image pipeline with third-party AWS kernels and a root-running metadata agent.

## Trust model

`gh attestation verify` checks that GitHub has a signed SLSA provenance attestation for the tarball under this repository and that the attested digest matches the file. It is not an OpenBSD signature and not a reproducible-build check. AWS kernel bundles are separate release artifacts from [ivoronin/openbsd-kernel-aws](https://github.com/ivoronin/openbsd-kernel-aws) with their own GitHub attestations; their pinned URLs and SHA256 values live in `builds/*.mk`.

The publishing templates and Packer plugins are separate inputs. The examples fetch templates from the same tag as the image release; inspect the template and pinned plugin versions before running Packer with production cloud credentials.

The installed system is packaged at the installer reboot, before first boot. The root password field is locked, `openbsd` is the image-created admin account, and the intended login path is an SSH key supplied through metadata. `openbsd` is in `wheel` and has passwordless `doas`, so anyone who can add metadata SSH keys has root on the instance.

Metadata is root-equivalent. Whoever controls NoCloud seed data or cloud metadata can install SSH keys for `openbsd`, set hostname, and run arbitrary `user-data` as root under `/bin/sh` at boot.

Images enable serial login on `tty00` at 115200 baud.

`generic` artifacts use the stock OpenBSD kernel from the installer. `aws` artifacts replace it with third-party kernel bundles from [ivoronin/openbsd-kernel-aws](https://github.com/ivoronin/openbsd-kernel-aws), including the out-of-tree [ENA driver](https://github.com/ivoronin/openbsd-driver-ena) and local EC2/Nitro patches. They are not OpenBSD Project kernels; `syspatch` may still patch official base files, but it does not maintain these kernels or cloud-tini, and unattended `sysupgrade` will install stock target-release kernels. Report AWS kernel, ENA, and Nitro failures here or in `openbsd-kernel-aws`; upstream OpenBSD bug reports need reproduction on stock OpenBSD. Upgrade only if you can install the matching target-release AWS kernel bundle into the upgraded filesystem before the final reboot.

## cloud-tini

cloud-tini is the metadata client every image ships with: [one base-Perl file](cloud-tini.pl), nothing from ports. `user-data` means a root `/bin/sh` script, not cloud-config.

| Source | Where | SSH key | Hostname | user-data |
|--------|-------|---------|----------|-----------|
| NoCloud | CIDATA disk with ISO9660 label `CIDATA` | `public-keys` | `local-hostname` | `user-data` file |
| EC2 | IMDS at `169.254.169.254`, IMDSv2 then v1 | `public-keys/<n>/openssh-key`, every key | `local-hostname` | `user-data` |
| GCE | `169.254.169.254` with `Metadata-Flavor: Google` | `attributes/ssh-keys`, with `user:` stripped | `hostname` | `attributes/user-data` |

It does not implement cloud-config modules.

### Boot flow

cloud-tini checks NoCloud first. Do not attach untrusted media labeled `CIDATA`: it can override cloud metadata, install admin SSH keys, set hostname, and run root `user-data`. If there is no CIDATA disk, cloud-tini probes EC2 and then GCE by fetching each source's `instance-id`, and uses whichever one answers.

For any source, SSH keys go into `~openbsd/.ssh/authorized_keys` in a managed block. GCE `user:key` entries still become `openbsd` admin keys after the `user:` prefix is stripped. cloud-tini rewrites that block each boot and leaves your other keys alone. Hostname goes into `/etc/myname` and `/etc/hosts`. User-data execution is gated by the source `instance-id`; cloud-tini runs it as root under `/bin/sh` and ignores the shebang.

## Choose an artifact

This project ships release artifacts, not public AMIs or GCE images. Import the artifact into your own cloud account or boot it locally.

Pick `aws` only for EC2/Nitro. Use `generic` for GCE, QEMU, vmd, and other platforms that can import a raw OpenBSD disk and expose one of the metadata sources cloud-tini understands. Pick `base` unless you need all OpenBSD install sets, including `comp`, `man`, `game`, and X sets.

`79` means OpenBSD 7.9. `base` installs the required kernel and base sets but excludes `man*`, `game*`, `x*`, and `comp*`; `full` uses the complete install set selection.

| Target | Artifact pattern |
|--------|------------------|
| EC2/Nitro amd64 | `openbsd-79-aws-base-amd64-bios-*.tar.gz` |
| EC2/Nitro arm64 | `openbsd-79-aws-base-arm64-uefi-*.tar.gz` |
| GCE amd64 | `openbsd-79-generic-base-amd64-bios-*.tar.gz` |
| QEMU or vmd amd64 | `openbsd-79-generic-base-amd64-bios-*.tar.gz` |
| QEMU arm64 | `openbsd-79-generic-base-arm64-uefi-*.tar.gz` |

## Get and verify a release

You need GitHub CLI `gh`, `tar`, and `gzip`.

```bash
set -euo pipefail

TAG=20260708
gh release download "$TAG" -R ivoronin/openbsd-cloudimg -p 'openbsd-79-aws-base-amd64-bios-*.tar.gz'
gh attestation verify openbsd-79-aws-base-amd64-bios-*.tar.gz \
  --repo ivoronin/openbsd-cloudimg \
  --signer-workflow github.com/ivoronin/openbsd-cloudimg/.github/workflows/build.yml \
  --source-ref "refs/tags/$TAG" \
  --deny-self-hosted-runners
tar xzf openbsd-79-aws-base-amd64-bios-*.tar.gz   # -> disk.raw
```

Release assets are gzip tarballs holding one file, `disk.raw`. AWS, QEMU, and vmd use the extracted raw disk. GCE imports the tarball directly. Extract each artifact in its own directory, because another archive will overwrite `disk.raw`.

## Publish to AWS

You need Packer 1.15.4 or newer and AWS credentials visible to the AWS SDK through environment variables or a shared profile. The input is an extracted `disk.raw` from an `aws` release artifact or a local AWS build.

After extracting an `aws` artifact, use the Packer template from the same tag to register `disk.raw` as a private AMI:

```bash
set -euo pipefail

TAG=20260708
curl -fsSLO "https://raw.githubusercontent.com/ivoronin/openbsd-cloudimg/$TAG/publish-aws.pkr.hcl"

export AWS_PROFILE=openbsd-cloudimg-publisher
export AWS_REGION=us-east-1

packer init publish-aws.pkr.hcl
packer build \
  -var image=disk.raw \
  -var image_name="openbsd-79-aws-base-amd64-bios-$TAG" \
  -var boot_mode=legacy-bios \
  -var architecture=x86_64 \
  publish-aws.pkr.hcl
```

For arm64, use the arm64 artifact and register it as a UEFI AMI:

```bash
set -euo pipefail

TAG=20260708
gh release download "$TAG" -R ivoronin/openbsd-cloudimg -p 'openbsd-79-aws-base-arm64-uefi-*.tar.gz'
gh attestation verify openbsd-79-aws-base-arm64-uefi-*.tar.gz \
  --repo ivoronin/openbsd-cloudimg \
  --signer-workflow github.com/ivoronin/openbsd-cloudimg/.github/workflows/build.yml \
  --source-ref "refs/tags/$TAG" \
  --deny-self-hosted-runners
tar xzf openbsd-79-aws-base-arm64-uefi-*.tar.gz

curl -fsSLO "https://raw.githubusercontent.com/ivoronin/openbsd-cloudimg/$TAG/publish-aws.pkr.hcl"

export AWS_PROFILE=openbsd-cloudimg-publisher
export AWS_REGION=us-east-1

packer init publish-aws.pkr.hcl
packer build \
  -var image=disk.raw \
  -var image_name="openbsd-79-aws-base-arm64-uefi-$TAG" \
  -var boot_mode=uefi \
  -var architecture=arm64 \
  publish-aws.pkr.hcl
```

## Supported instance families

Support is per instance family. Release `20260708` was boot-tested on the
current Nitro matrix we use for AWS e2e: arm64 Graviton `t4g`, `c6g`, `c7g`,
`c8g`, `c9g`; amd64 Intel `c5`, `c6i`, `c7i`, `c8i`; and amd64 AMD `c6a`,
`c7a`, `c8a`.

## Publish to GCE via GCS

You need Packer 1.15.4 or newer, `gcloud`, Google credentials available to Packer, and an existing GCS bucket. GCE imports the release `.tar.gz` as-is, so keep the archive intact and do not extract it.

```bash
set -euo pipefail

TAG=20260708
IMAGE_TAG=${TAG//./-}
gh release download "$TAG" -R ivoronin/openbsd-cloudimg -p 'openbsd-79-generic-base-amd64-bios-*.tar.gz'
gh attestation verify openbsd-79-generic-base-amd64-bios-*.tar.gz \
  --repo ivoronin/openbsd-cloudimg \
  --signer-workflow github.com/ivoronin/openbsd-cloudimg/.github/workflows/build.yml \
  --source-ref "refs/tags/$TAG" \
  --deny-self-hosted-runners

IMAGE=openbsd-79-generic-base-amd64-bios-*.tar.gz
curl -fsSLO "https://raw.githubusercontent.com/ivoronin/openbsd-cloudimg/$TAG/publish-gce.pkr.hcl"

export BUCKET=my-import-bucket
export GCP_PROJECT=$(gcloud config get-value project)

packer init publish-gce.pkr.hcl
packer build \
  -var "image=$IMAGE" \
  -var image_name="openbsd-79-generic-base-amd64-bios-$IMAGE_TAG" \
  -var project="$GCP_PROJECT" \
  -var bucket="$BUCKET" \
  publish-gce.pkr.hcl
```

## Build locally

You need `uv`, Packer 1.15.4 or newer, QEMU, and `pigz`. Native acceleration needs matching host and target architecture; otherwise use `ACCEL=tcg`. arm64 builds need edk2 aarch64 UEFI firmware, for example `qemu-efi-aarch64` on Debian/Ubuntu.

List the configured builds:

```bash
make builds
```

Build one image:

```bash
make build BUILD=79-aws-base-amd64
```

Output lands at `output/images/<name>/disk.raw`, where `<name>` is `openbsd-<build>-<firmware>`.

Local QEMU/vmd boot uses a NoCloud `CIDATA` disk; see [LOCAL.md](LOCAL.md).

Advanced build knobs:

- `SETS` and `DISK_SIZE` live in `builds/*.mk`. `SETS` is the OpenBSD installer set selection; `DISK_SIZE` is the Packer disk size. The `*-base-*` names are repo-local shorthand; they still install the required OpenBSD kernel and base sets, but exclude `man*`, `game*`, `x*`, and `comp*`.
- `ACCEL=tcg` forces QEMU emulation. By default, `tools/host.py` picks native acceleration when host and target architecture match, and `tcg` otherwise.
- `EFI_CODE=...` and `EFI_VARS=...` override UEFI firmware paths when auto-detection is wrong for your host.
- `BUNDLES=/path/to/bundle.tgz` replaces manifest bundles with local bundles carried inside `site79.tgz`. This is an explicit supply-chain escape hatch: it bypasses manifest URL/SHA256 checks; each bundle must contain an executable `install.sh`, and that script runs as root during image install.

AWS build files consume pinned kernel bundles declared in `builds/*.mk`. To move to a newer bundle, update `BUNDLE_NAMES`, `BUNDLE_URL.<name>`, and `BUNDLE_SHA256.<name>` in the matching files, run `make build` and `make test`, then boot the imported AMI on the Nitro instance families you intend to support. `make test` does not exercise ENA.

## Releases

Tags are date batches: `YYYYMMDD`, or `YYYYMMDD.N` for another release on the same UTC day. The tag is not the OpenBSD version.

A release builds every file in `builds/`. Assets are named:

```text
openbsd-<build>-<firmware>-<gitref>-<timestamp>.tar.gz
```

Artifacts are snapshots; for newer OpenBSD errata or AWS kernel bundles, cut a new release.

## License

[ISC](LICENSE)
