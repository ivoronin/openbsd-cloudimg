#!/bin/ksh
# Runs in the throwaway builder VM (full install + comp toolchain) for one target:
# patches and builds the kernel under a custom config name, then packs the finished
# site set (kernel + KARL kit + install.site) into /home/site for the host to pull.
# Args: $1 = version (7.8), $2 = build target (aws)
set -eu
ver="$1"; target="$2"
conf=$(echo "$target" | tr '[:lower:]' '[:upper:]')   # aws -> AWS
machine=$(machine)
tdir=/home/build/$target
src=$tdir/$ver
stage=/home/site
tag=$(echo "$ver" | tr -d .)

# Fetch and signify-verify the kernel source (base ships the release pubkey).
cd /usr/src
ftp -V -o SHA256.sig "https://cdn.openbsd.org/pub/OpenBSD/$ver/SHA256.sig"
ftp -V -o sys.tar.gz "https://cdn.openbsd.org/pub/OpenBSD/$ver/sys.tar.gz"
signify -C -p "/etc/signify/openbsd-$tag-base.pub" -x SHA256.sig sys.tar.gz
tar xzf sys.tar.gz && rm -f sys.tar.gz SHA256.sig

# Files first (so patches can target them): copy each submodule's sys/ overlay into
# /usr/src - the openbsd-ena driver mirrors the source tree under sys/dev/pci/.
if [ -d "$src/files" ]; then
	for sub in "$src"/files/*/sys; do
		[ -d "$sub" ] || continue
		(cd "$(dirname "$sub")" && pax -rw sys /usr/src)
	done
	rm -f /usr/src/sys/dev/pci/ena.files.fragment /usr/src/sys/dev/pci/.keep
fi
# Patches second: nvme MQES clamp, the amd64 PCIe (acpipci MSI-for-Amazon) fix, ena wiring.
if [ -d "$src/patches" ]; then
	for p in "$src"/patches/*.patch; do
		[ -e "$p" ] || continue
		echo "build: applying $(basename "$p")"
		patch -p0 -d /usr/src < "$p"
	done
fi
# pcidevs.h / pcidevs_data.h are generated from the master - ena.patch edits only the
# master, so regenerate via the tree's own target (rm + devlist2h.awk); this is where
# PCI_VENDOR_AMAZON and the ENA ids land.
(cd /usr/src/sys/dev/pci && make pcidevs.h pcidevs_data.h)

# Custom config (uname AWS.MP, and syspatch leaves the kernel alone): AWS is GENERIC
# minus drm plus the ena instance; AWS.MP re-points GENERIC.MP's include at it. Both
# are built - AWS.MP as /bsd (the EC2 kernel), AWS as /bsd.sp.
cd "/usr/src/sys/arch/$machine/conf"
# agp too: on amd64 intagp hangs off inteldrm, so stripping drm orphans agp* at intagp?.
sed -E '/(inteldrm|radeondrm|amdgpu|agp)/d' GENERIC > "$conf"
echo 'ena* at pci?  # Amazon Elastic Network Adapter' >> "$conf"
sed "s#conf/GENERIC\"#conf/$conf\"#" GENERIC.MP > "$conf.MP"

for c in "$conf" "$conf.MP"; do
	cd "/usr/src/sys/arch/$machine/conf"
	config "$c"
	cd "/usr/src/sys/arch/$machine/compile/$c"
	make obj >/dev/null
	make -j"$(sysctl -n hw.ncpu)"
done

# Pack the site set here on OpenBSD (clean tar). The KARL relink kit is built as
# src/etc/Makefile builds the stock kernel.tgz. Explicit files only, no directory
# members, so extraction never rewrites / on the target.
root=$(mktemp -d)
mp="/usr/src/sys/arch/$machine/compile/$conf.MP"
sp="/usr/src/sys/arch/$machine/compile/$conf"
install -m 644 "$mp/obj/bsd"        "$root/bsd.aws"
install -m 644 "$sp/obj/bsd"        "$root/bsd.sp.aws"
install -m 644 "$tdir/install.site" "$root/install.site"
# Relink kits for BOTH configs (like stock GENERIC + GENERIC.MP), so reorder_kernel
# can KARL whichever is /bsd - users may boot the SP kernel to dodge an MP bug.
( cd "/usr/src/sys/arch/$machine/compile" &&
  tar -chzf "$root/bsd.relink.tgz" -s ',/obj/,/,' \
      "$conf"/obj/*.o    "$conf"/obj/Makefile    "$conf"/obj/ld.script    "$conf"/obj/makegap.sh \
      "$conf.MP"/obj/*.o "$conf.MP"/obj/Makefile "$conf.MP"/obj/ld.script "$conf.MP"/obj/makegap.sh )
mkdir -p "$stage"
tar -C "$root" -czf "$stage/site$tag.tgz" ./install.site ./bsd.aws ./bsd.sp.aws ./bsd.relink.tgz
( cd "$stage" && sha256 "site$tag.tgz" > SHA256 )
echo "build: staged $(ls -l "$stage")"
