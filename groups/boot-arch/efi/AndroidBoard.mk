

# Rules to create bootloader zip file, a precursor to the bootloader
# image that is stored in the target-files-package. There's also
# metadata file which indicates how large to make the VFAT filesystem
# image

ifeq ($(TARGET_UEFI_ARCH),i386)
efi_default_name := bootia32.efi
LOADER_TYPE := linux-x86
else
efi_default_name := bootx64.efi
LOADER_TYPE := linux-x86_64
endif

# (pulled from build/core/Makefile as this gets defined much later)
# Pick a reasonable string to use to identify files.
ifneq "" "$(filter eng.%,$(BUILD_NUMBER))"
# BUILD_NUMBER has a timestamp in it, which means that
# it will change every time.  Pick a stable value.
FILE_NAME_TAG := eng.$(USER)
else
FILE_NAME_TAG := $(BUILD_NUMBER)
endif

LOADER_PREBUILT := hardware/intel/efi_prebuilts/

kernelflinger := $(PRODUCT_OUT)/efi/kernelflinger.efi

ifeq ($(BOARD_USE_UEFI_SHIM),true)

# EFI binaries that go in the installed device's EFI system partition
BOARD_FIRST_STAGE_LOADER := \
    $(LOADER_PREBUILT)/uefi_shim/$(LOADER_TYPE)/shim.efi

BOARD_EXTRA_EFI_MODULES := \
    $(LOADER_PREBUILT)/uefi_shim/$(LOADER_TYPE)/MokManager.efi \
    $(kernelflinger)

# We need kernelflinger.efi packaged inside the fastboot boot image to be
# able to work with MCG's EFI fastboot stub
USERFASTBOOT_2NDBOOTLOADER := $(kernelflinger)

else # !BOARD_USE_UEFI_SHIM

BOARD_FIRST_STAGE_LOADER := $(kernelflinger)
BOARD_EXTRA_EFI_MODULES :=
USERFASTBOOT_2NDBOOTLOADER :=
endif

# We stash a copy of BIOSUPDATE.fv so the FW sees it, applies the
# update, and deletes the file. Follows Google's desire to update
# all bootloader pieces with a single "fastboot flash bootloader"
# command. We place the fastboot.img in the ESP for the same reason.
# Since it gets deleted we can't do incremental updates of it, we
# keep a copy in the system partition for this purpose.
intermediates := $(call intermediates-dir-for,PACKAGING,bootloader_zip)
bootloader_zip := $(intermediates)/bootloader.zip
$(bootloader_zip): intermediates := $(intermediates)
$(bootloader_zip): efi_root := $(intermediates)/root
$(bootloader_zip): \
		$(TARGET_DEVICE_DIR)/AndroidBoard.mk \
		$(BOARD_FIRST_STAGE_LOADER) \
		$(BOARD_EXTRA_EFI_MODULES) \
		$(BOARD_SFU_UPDATE) \
		| $(ACP) \

	$(hide) rm -rf $(efi_root)
	$(hide) rm -f $@
	$(hide) mkdir -p $(efi_root)
	$(hide) mkdir -p $(efi_root)/EFI/BOOT
ifneq ($(BOARD_EXTRA_EFI_MODULES),)
	$(hide) $(ACP) $(BOARD_EXTRA_EFI_MODULES) $(efi_root)/
endif
ifneq ($(BOARD_SFU_UPDATE),)
	$(hide) $(ACP) $(BOARD_SFU_UPDATE) $(efi_root)/BIOSUPDATE.fv
endif
	$(hide) $(ACP) $(BOARD_FIRST_STAGE_LOADER) $(efi_root)/loader.efi
	$(hide) $(ACP) $(BOARD_FIRST_STAGE_LOADER) $(efi_root)/EFI/BOOT/$(efi_default_name)
	$(hide) (cd $(efi_root) && zip -qry ../$(notdir $@) .)

bootloader_metadata := $(intermediates)/bootloader-size.txt
$(bootloader_metadata):
	$(hide) mkdir -p $(dir $@)
	$(hide) echo $(BOARD_BOOTLOADER_PARTITION_SIZE) > $@

INSTALLED_RADIOIMAGE_TARGET += $(bootloader_zip) $(bootloader_metadata)

# Rule to create $(OUT)/bootloader image, binaries within are signed with
# testing keys

bootloader_bin := $(PRODUCT_OUT)/bootloader
$(bootloader_bin): \
		$(bootloader_zip) \
		$(MKDOSFS) \
		$(MCOPY) \
		$(BOOTLOADER_ADDITIONAL_DEPS) \
		device/intel/build/bootloader_from_zip \

	$(hide) device/intel/build/bootloader_from_zip \
		--size $(BOARD_BOOTLOADER_PARTITION_SIZE) \
		$(BOOTLOADER_ADDITIONAL_ARGS) \
		--zipfile $(bootloader_zip) \
		$@

droidcore: $(bootloader_bin)

.PHONY: bootloader
bootloader: $(bootloader_bin)
$(call dist-for-goals,droidcore,$(bootloader_bin):$(TARGET_PRODUCT)-bootloader-$(FILE_NAME_TAG))

fastboot_usb_bin := $(PRODUCT_OUT)/fastboot-usb.img
$(fastboot_usb_bin): \
		$(bootloader_zip) \
		$(MKDOSFS) \
		$(MCOPY) \
		$(BOOTLOADER_ADDITIONAL_DEPS) \
		device/intel/build/bootloader_from_zip \

	$(hide) device/intel/build/bootloader_from_zip \
		$(BOOTLOADER_ADDITIONAL_ARGS) \
		--zipfile $(bootloader_zip) \
		--extra-size 10485760 \
		--bootable \
		$@

# Build when 'make' is run with no args
droidcore: $(fastboot_usb_bin)

.PHONY: userfastboot-usb
userfastboot-usb: $(fastboot_usb_bin)

$(call dist-for-goals,droidcore,$(fastboot_usb_bin):$(TARGET_PRODUCT)-fastboot-usb-$(FILE_NAME_TAG).img)

ifneq ($(BOARD_SFU_UPDATE),)
$(call dist-for-goals,droidcore,$(BOARD_SFU_UPDATE):$(TARGET_PRODUCT)-sfu-$(FILE_NAME_TAG).fv)
endif

$(call dist-for-goals,droidcore,$(LOADER_PREBUILT)/efitools/$(LOADER_TYPE)/LockDown.efi:LockDown.efi)

ifeq ($[fastboot],efi)
# For fastboot-uefi we need to parse gpt.ini into
# a binary format.

GPT_INI2BIN := ./device/intel/common/gpt_bin/gpt_ini2bin.py

$(BOARD_GPT_BIN): $(BOARD_GPT_INI)
	$(hide) $(GPT_INI2BIN) $< > $@
	$(hide) echo GEN $(notdir $@)

else
INSTALLED_RADIOIMAGE_TARGET += $(PRODUCT_OUT)/fastboot.img
endif

ifneq ($(EFI_IFWI_BIN),)
$(call dist-for-goals,droidcore,$(EFI_IFWI_BIN):$(TARGET_PRODUCT)-ifwi-$(FILE_NAME_TAG).bin)
endif
