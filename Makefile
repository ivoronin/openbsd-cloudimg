VER          ?= 7.9
ARCH         ?= amd64
FLAVOR       ?= base
ACCEL        ?= kvm
CLOUD_INIT_SOURCE  ?=
# Optional debug flags - set to 1 to drop a provisioning step from the build.
DISABLE_SYSPATCH   ?=
DISABLE_CLOUD_INIT ?=
DISABLE_CLEANUP    ?=
# arm64 UEFI firmware (qemu does not autoload it for virt). CODE is read-only,
# VARS a writable template. Auto-located across common qemu dirs; override else.
EFI_CODE     ?= $(firstword $(wildcard /opt/homebrew/share/qemu/edk2-aarch64-code.fd /usr/share/qemu/edk2-aarch64-code.fd /usr/share/AAVMF/AAVMF_CODE.fd))
EFI_VARS     ?= $(firstword $(wildcard /opt/homebrew/share/qemu/edk2-arm-vars.fd /usr/share/qemu/edk2-arm-vars.fd /usr/share/AAVMF/AAVMF_VARS.fd))
ISO_CHECKSUM ?= $(shell jq -r '.[] | select(.version=="$(VER)" and .arch=="$(ARCH)") | .iso_checksum' images.json)

NAME  = openbsd-$(VER)-$(ARCH)-$(FLAVOR)
OUT    = output/build/$(ARCH)/$(VER)/$(FLAVOR)
IMG    = $(OUT)/$(NAME).img
IMGGZ  = $(OUT)/$(NAME).img.gz

SOURCES = build.pkr.hcl install.conf.pkrtpl cloud-init.pl $(wildcard scripts/*)

.PHONY: build smoke compress clean
.SUFFIXES:

build: $(IMG)

compress: $(IMGGZ)

SMOKE_SOURCES = $(if $(CLOUD_INIT_SOURCE),$(CLOUD_INIT_SOURCE),imds cidata)

smoke: $(IMG)
	packer init smoke.pkr.hcl
	@for s in $(SMOKE_SOURCES); do \
	  echo "=== smoke: cloud_init_source=$$s ==="; \
	  packer build -force -var cloud_init_source=$$s -var image=$(IMG) -var version=$(VER) -var arch=$(ARCH) -var flavor=$(FLAVOR) -var accelerator=$(ACCEL) -var efi_code=$(EFI_CODE) -var efi_vars=$(EFI_VARS) smoke.pkr.hcl || exit 1; \
	done

$(IMG): $(SOURCES) images.json
	packer init build.pkr.hcl
	packer build -force \
	  -var version=$(VER) \
	  -var arch=$(ARCH) \
	  -var flavor=$(FLAVOR) \
	  -var accelerator=$(ACCEL) \
	  -var iso_checksum=$(ISO_CHECKSUM) \
	  -var efi_code=$(EFI_CODE) \
	  -var efi_vars=$(EFI_VARS) \
	  -var disable_syspatch=$(if $(DISABLE_SYSPATCH),true,false) \
	  -var disable_cloud_init=$(if $(DISABLE_CLOUD_INIT),true,false) \
	  -var disable_cleanup=$(if $(DISABLE_CLEANUP),true,false) \
	  build.pkr.hcl

$(IMGGZ): $(IMG)
	pigz -9 -c $< > $@

clean:
	rm -rf output
