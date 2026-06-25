VER          ?= 7.9
# Build-host arch in the project's naming (amd64/arm64); drives ARCH and ACCEL defaults.
HOST_ARCH    := $(patsubst aarch64,arm64,$(patsubst x86_64,amd64,$(shell uname -m)))
ARCH         ?= $(HOST_ARCH)
PROFILE       ?= base
# Flavor: generic (stock kernel) or aws (patched kernel via the builder stage).
FLAVOR        ?= generic
# Boot firmware: uefi (GPT) or, on amd64 only, bios (MBR). Defaults uefi for aws/arm64.
FIRMWARE     ?= $(if $(filter aws,$(FLAVOR)),uefi,$(if $(filter arm64,$(ARCH)),uefi,bios))
# QEMU accelerator: native (kvm/hvf) when target arch matches the host, else tcg.
ACCEL        ?= $(if $(filter $(ARCH),$(HOST_ARCH)),$(if $(filter Darwin,$(shell uname -s)),hvf,kvm),tcg)
# UEFI firmware, auto-located across common qemu/distro dirs (override if not found).
EFI_CODE     ?= $(firstword $(wildcard $(if $(filter arm64,$(ARCH)),\
/opt/homebrew/share/qemu/edk2-aarch64-code.fd /usr/share/qemu/edk2-aarch64-code.fd /usr/share/AAVMF/AAVMF_CODE.fd,\
/opt/homebrew/share/qemu/edk2-x86_64-code.fd /usr/share/qemu/edk2-x86_64-code.fd /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd)))
EFI_VARS     ?= $(firstword $(wildcard $(if $(filter arm64,$(ARCH)),\
/opt/homebrew/share/qemu/edk2-arm-vars.fd /usr/share/qemu/edk2-arm-vars.fd /usr/share/AAVMF/AAVMF_VARS.fd,\
/opt/homebrew/share/qemu/edk2-i386-vars.fd /usr/share/qemu/edk2-i386-vars.fd /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd)))
ISO_CHECKSUM ?= $(shell jq -r '.[] | select(.version=="$(VER)" and .arch=="$(ARCH)") | .iso_checksum' images.json)
# Every VER/ARCH must be pinned in images.json.
ifeq ($(ISO_CHECKSUM),)
$(error VER=$(VER) ARCH=$(ARCH) has no ISO checksum in images.json)
endif

NAME  = openbsd-$(VER)-$(ARCH)-$(FLAVOR)-$(PROFILE)-$(FIRMWARE)
OUT    = output/images/$(ARCH)/$(VER)/$(FLAVOR)/$(PROFILE)/$(FIRMWARE)
IMG    = $(OUT)/$(NAME).img
IMGXZ  = $(OUT)/$(NAME).img.xz
# The site set the builder produces, ridden as cd1. Keyed by arch/ver/flavor, kept
# outside $(OUT) (which -force wipes).
TAG    = $(subst .,,$(VER))
SETDIR = output/site/$(ARCH)/$(VER)/$(FLAVOR)
SITE   = $(SETDIR)/site$(TAG).tgz
# Only non-generic targets ship a site set.
SITE_IF = $(if $(filter-out generic,$(FLAVOR)),$(SITE))

SOURCES = imager.pkr.hcl install.conf.pkrtpl cloud-init.pl $(wildcard scripts/*)

.PHONY: images site test compress clean
.SUFFIXES:

images: $(IMG)

site: $(SITE_IF)

compress: $(IMGXZ)

TEST_SOURCES = imds cidata

test: $(IMG)
	packer init tester.pkr.hcl
	@for s in $(TEST_SOURCES); do \
	  echo "=== test: cloud_init_source=$$s ==="; \
	  packer build -force -var cloud_init_source=$$s -var image=$(IMG) -var version=$(VER) -var arch=$(ARCH) -var profile=$(PROFILE) -var firmware=$(FIRMWARE) -var accelerator=$(ACCEL) -var efi_code=$(EFI_CODE) -var efi_vars=$(EFI_VARS) tester.pkr.hcl || exit 1; \
	done

# The builder VM compiles the kernel and packs the whole sets set + SHA256.
$(SITE): builder.pkr.hcl builder.conf.pkrtpl flavors/$(FLAVOR)/builder.sh flavors/$(FLAVOR)/install.site \
         $(wildcard flavors/$(FLAVOR)/$(VER)/patches/* flavors/$(FLAVOR)/$(VER)/files/*) images.json
	packer init builder.pkr.hcl
	packer build -force \
	  -var version=$(VER) \
	  -var arch=$(ARCH) \
	  -var flavor=$(FLAVOR) \
	  -var accelerator=$(ACCEL) \
	  -var iso_checksum=$(ISO_CHECKSUM) \
	  -var efi_code=$(EFI_CODE) \
	  -var efi_vars=$(EFI_VARS) \
	  builder.pkr.hcl

$(IMG): $(SOURCES) $(SITE_IF) images.json
	packer init imager.pkr.hcl
	packer build -force \
	  -var version=$(VER) \
	  -var arch=$(ARCH) \
	  -var flavor=$(FLAVOR) \
	  -var profile=$(PROFILE) \
	  -var firmware=$(FIRMWARE) \
	  -var accelerator=$(ACCEL) \
	  -var iso_checksum=$(ISO_CHECKSUM) \
	  -var efi_code=$(EFI_CODE) \
	  -var efi_vars=$(EFI_VARS) \
	  -var set_dir=$(SETDIR) \
	  imager.pkr.hcl

$(IMGXZ): $(IMG)
	xz -T0 -c $< > $@

clean:
	rm -rf output
