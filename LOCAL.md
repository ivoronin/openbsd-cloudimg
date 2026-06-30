# Local Boot

QEMU and vmd use the same metadata path as downloaded artifacts: attach a NoCloud `CIDATA` disk with an SSH key for the image-created `openbsd` account.

For QEMU, you need QEMU, `xorriso`, and SSH client tools. For vmd, you need OpenBSD `vmd`/`vmctl`, `mkhybrid` from base, and SSH client tools.

For a downloaded release, extract the archive first and use the `disk.raw` inside it:

```bash
DISK=${DISK:-disk.raw}
```

For a local build:

```bash
DISK=output/images/openbsd-79-generic-base-amd64-bios/disk.raw
```

Generate the key and NoCloud `meta-data`:

```bash
ssh-keygen -t ed25519 -f ./id_openbsd -N ''
cat > meta-data <<EOF
local-hostname: obsd1
public-keys:
  - $(cat id_openbsd.pub)
EOF
```

Add an optional `user-data` file beside `meta-data` for the boot-flow user-data path. cloud-tini runs it as root under `/bin/sh`.

The run is gated on `instance-id`: add an optional `instance-id:` to `meta-data` and bump it to re-run `user-data`. With no `instance-id`, user-data runs exactly once. SSH keys and hostname are re-applied every boot either way.

## QEMU

`xorriso` builds the CIDATA ISO:

```bash
xorriso -as mkisofs -V CIDATA -J -r -o cidata.iso meta-data

ACCEL=${ACCEL:-kvm}   # Linux/KVM; use ACCEL=hvf on macOS or ACCEL=tcg without native accel

qemu-system-x86_64 -accel "$ACCEL" -m 1G -nographic \
  -drive file="$DISK",format=raw,if=virtio \
  -nic user,model=virtio,hostfwd=tcp::2222-:22 \
  -cdrom cidata.iso

ssh -i id_openbsd -p 2222 openbsd@localhost
```

## vmd

`mkhybrid` from OpenBSD base builds the CIDATA ISO for vmd. Keep `-r`; it adds the Rock Ridge names cloud-tini reads. Without it, `meta-data` becomes `META_DAT`.

```bash
mkhybrid -o cidata.iso -r -V CIDATA meta-data

# -L gives the VM a local address; the first such VM gets 100.64.0.3.
rcctl start vmd
vmctl start obsd1 -m 1G -L \
  -d "$DISK" \
  -d cidata.iso

ssh -i id_openbsd openbsd@100.64.0.3
```
