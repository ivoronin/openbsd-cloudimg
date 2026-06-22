VER          ?= 7.9
ARCH         ?= amd64
FLAVOR       ?= base
ACCEL        ?= kvm
# arm64 UEFI firmware (qemu does not autoload it for virt). CODE is read-only,
# VARS a writable template. Auto-located across common qemu dirs; override else.
EFI_CODE     ?= $(firstword $(wildcard /opt/homebrew/share/qemu/edk2-aarch64-code.fd /usr/share/qemu/edk2-aarch64-code.fd /usr/share/AAVMF/AAVMF_CODE.fd))
EFI_VARS     ?= $(firstword $(wildcard /opt/homebrew/share/qemu/edk2-arm-vars.fd /usr/share/qemu/edk2-arm-vars.fd /usr/share/AAVMF/AAVMF_VARS.fd))
ISO_CHECKSUM ?= $(shell jq -r '.[] | select(.version=="$(VER)" and .arch=="$(ARCH)") | .iso_checksum' images.json)

NAME  = openbsd-$(VER)-$(ARCH)-$(FLAVOR)
OUT   = output/$(FLAVOR)
IMG    = $(OUT)/$(NAME).img
IMGZST = $(OUT)/$(NAME).img.zst

SOURCES = openbsd.pkr.hcl install.conf.pkrtpl cloud-init.sh $(wildcard scripts/*)

.PHONY: build smoke compress clean
.SUFFIXES:

build: $(IMG)

compress: $(IMGZST)

smoke: $(IMG)
	packer init test.pkr.hcl
	packer build -force -var image=$(IMG) -var arch=$(ARCH) -var accelerator=$(ACCEL) -var efi_code=$(EFI_CODE) -var efi_vars=$(EFI_VARS) test.pkr.hcl

$(IMG): $(SOURCES) images.json
	packer init openbsd.pkr.hcl
	packer build -force \
	  -var version=$(VER) \
	  -var arch=$(ARCH) \
	  -var flavor=$(FLAVOR) \
	  -var accelerator=$(ACCEL) \
	  -var iso_checksum=$(ISO_CHECKSUM) \
	  -var efi_code=$(EFI_CODE) \
	  -var efi_vars=$(EFI_VARS) \
	  openbsd.pkr.hcl

$(IMGZST): $(IMG)
	zstd -T0 -19 --long=27 -f -o $@ $<

clean:
	rm -rf output
