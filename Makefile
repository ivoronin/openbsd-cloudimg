UV ?= uv

HOSTTOOL = $(UV) run tools/host.py
DOWNLOAD = $(UV) run tools/download.py
MKSITE = $(UV) run tools/mksite.py

BUILDS = $(sort $(patsubst builds/%.mk,%,$(wildcard builds/*.mk)))

HOST_ARCH ?= $(shell $(HOSTTOOL) arch)
BUILD ?= 79-generic-base-$(HOST_ARCH)
BUILD_MANIFEST = builds/$(BUILD).mk

include $(BUILD_MANIFEST)

BUNDLE_DIR = $(CURDIR)/output/bundles
ACCEL ?= $(shell $(HOSTTOOL) accel --arch $(BUILD_ARCH))
EFI_CODE ?= $(shell $(HOSTTOOL) efi-code --arch $(BUILD_ARCH))
EFI_VARS ?= $(shell $(HOSTTOOL) efi-vars --arch $(BUILD_ARCH))
IMAGE_NAME_DEFAULT = openbsd-$(BUILD)-$(BUILD_FIRMWARE)
IMAGE_NAME ?= $(IMAGE_NAME_DEFAULT)
BOOT_MODE = $(if $(filter uefi,$(BUILD_FIRMWARE)),uefi,legacy-bios)
AMI_ARCH = $(if $(filter arm64,$(BUILD_ARCH)),arm64,x86_64)
BUCKET ?=
GCP_PROJECT ?= $(shell gcloud config get-value project 2>/dev/null)
IMAGE_DIR = $(CURDIR)/output/images/$(IMAGE_NAME_DEFAULT)
IMAGE = $(IMAGE_DIR)/disk.raw
ARCHIVE = $(IMAGE_DIR)/$(IMAGE_NAME_DEFAULT).tar.gz
SET_DIR = $(CURDIR)/output/sets/openbsd-$(BUILD)
SITE = $(SET_DIR)/site$(OPENBSD_TAG).tgz
MANIFEST_BUNDLES = $(addprefix $(BUNDLE_DIR)/,$(BUNDLE_NAMES))
SITE_BUNDLES = $(if $(filter undefined,$(origin BUNDLES)),$(MANIFEST_BUNDLES),$(BUNDLES))
IMAGE_PACKER_VARS = \
	-var 'arch=$(BUILD_ARCH)' \
	-var 'disk_size=$(DISK_SIZE)' \
	-var 'firmware=$(BUILD_FIRMWARE)' \
	-var 'image_name=$(IMAGE_NAME_DEFAULT)' \
	-var 'iso_checksum=$(ISO_CHECKSUM)' \
	-var 'iso_sets_path=$(ISO_SETS_PATH)' \
	-var 'iso_url=$(ISO_URL)' \
	-var 'set_dir=$(SET_DIR)' \
	-var 'sets=$(SETS)'
TEST_PACKER_VARS = \
	-var 'arch=$(BUILD_ARCH)' \
	-var 'firmware=$(BUILD_FIRMWARE)' \
	-var 'image_name=$(IMAGE_NAME_DEFAULT)'
PUBLISH_AWS_PACKER_VARS = \
	-var 'image=$(IMAGE)' \
	-var 'image_name=$(IMAGE_NAME)' \
	-var 'boot_mode=$(BOOT_MODE)' \
	-var 'architecture=$(AMI_ARCH)'
PUBLISH_GCE_PACKER_VARS = \
	-var 'image=$(ARCHIVE)' \
	-var 'image_name=$(IMAGE_NAME)' \
	-var 'project=$(GCP_PROJECT)' \
	-var 'bucket=$(BUCKET)'
QEMU_PACKER_VARS = \
	-var 'accelerator=$(ACCEL)' \
	-var 'efi_code=$(EFI_CODE)' \
	-var 'efi_vars=$(EFI_VARS)'

ifneq ($(origin BUNDLES),undefined)
export BUNDLES
endif

.PHONY: builds matrix prepare build site test compress publish-aws publish-gce clean
.SUFFIXES:
.DEFAULT_GOAL := build

builds:
	@printf '%s\n' $(BUILDS)

matrix:
	@printf '%s\n' $(BUILDS) | jq -Rnc '[inputs]'

prepare site: $(SITE)

$(SITE): tools/mksite.py install.site cloud-tini.pl $(BUILD_MANIFEST) $(SITE_BUNDLES)
	@mkdir -p $(@D)
	$(MKSITE) $@ install.site cloud-tini.pl $(SITE_BUNDLES)

$(BUNDLE_DIR)/%.tgz: $(BUILD_MANIFEST) tools/download.py
	$(DOWNLOAD) "$(BUNDLE_URL.$(@F))" "$(BUNDLE_SHA256.$(@F))" "$@"

build: $(IMAGE)

$(IMAGE): image.pkr.hcl install.conf.pkrtpl $(SITE)
	packer init image.pkr.hcl
	packer build -force $(IMAGE_PACKER_VARS) $(QEMU_PACKER_VARS) image.pkr.hcl

test: $(IMAGE)
	packer init test.pkr.hcl
	@rm -rf "output/tests/$(IMAGE_NAME_DEFAULT)"
	@for s in imds cidata gce; do \
	  test_dir="output/tests/$(IMAGE_NAME_DEFAULT)/$$s"; \
	  console_log="$$test_dir/console.log"; \
	  work_dir="$$test_dir/work"; \
	  echo "=== test: cloud_tini_source=$$s ==="; \
	  mkdir -p "$$test_dir"; \
	  packer build -force $(TEST_PACKER_VARS) $(QEMU_PACKER_VARS) -var "cloud_tini_source=$$s" -var "console_log=$$console_log" -var "work_dir=$$work_dir" -var 'image=$(IMAGE)' test.pkr.hcl || exit 1; \
	  rm -rf "$$work_dir"; \
	done

compress: $(ARCHIVE)

$(ARCHIVE): $(IMAGE)
	tar -C "$(IMAGE_DIR)" -cf - disk.raw | pigz > "$(ARCHIVE)"

publish-aws: $(IMAGE)
	packer init publish-aws.pkr.hcl
	packer build $(PUBLISH_AWS_PACKER_VARS) publish-aws.pkr.hcl

publish-gce: $(ARCHIVE)
	@test -n "$(BUCKET)" && test -n "$(GCP_PROJECT)" || \
	  { echo "set BUCKET=... (GCS) with GCP ADC creds; GCP_PROJECT defaults from gcloud config" >&2; exit 1; }
	packer init publish-gce.pkr.hcl
	packer build $(PUBLISH_GCE_PACKER_VARS) publish-gce.pkr.hcl

clean:
	rm -rf output
