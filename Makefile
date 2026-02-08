NPROC = $(shell nproc)

VERILATOR := verilator
ifdef VERILATOR_ROOT
VERILATOR := $(VERILATOR_ROOT)/bin/verilator
endif

SIM_NAME ?= image_processing
SIM_DIR  ?= $(SIM_NAME)-sim

SV_SOURCE_FILES := $(wildcard hdl/*.sv)
TB_FILE := $(wildcard tb/*.sv)
HDL_PARAM ?= hdl/parameters.svh
KERNEL ?= SOBEL_X

GOLDEN_DIR := test_vectors/golden

PIXELS_FILE ?= test_vectors/input/pixels_in.txt
IMAGE_FILE ?= test_vectors/images/gemi-anadolu.jpg
RANDOM_IMAGE_FILE ?= test_vectors/images/random_image.jpg
OUTPUT_FILE ?= test_vectors/fpga_out/pixel_out_fpga.txt
GOLDEN_FILE ?= $(GOLDEN_DIR)/ref.txt
REQUIREMENTS_FILE ?= sw/requirements.txt

COMPILE_ARGS += --prefix $(SIM_NAME) -o $(SIM_NAME)
COMPILE_ARGS += +incdir+hdl

GEN_PARAM_IMAGE ?= $(IMAGE_FILE)

EXTRA_ARGS += \
	--sv \
	--timescale 1ns/1ps \
	--error-limit 100 \
	--trace \
	--threads $(NPROC)

EXTRA_ARGS += +define+PIXELS_FILE=\"$(PIXELS_FILE)\"
EXTRA_ARGS += +define+PIXELS_OUT_FILE=\"$(OUTPUT_FILE)\"


# Map CLI kernel names to SystemVerilog enums
ifeq ($(KERNEL),SOBEL_X)
  KERNEL_TYPE := KERNEL_SOBEL
else ifeq ($(KERNEL),BOX)
  KERNEL_TYPE := KERNEL_BOX
else ifeq ($(KERNEL),GAUSS)
  KERNEL_TYPE := KERNEL_GAUSS
else
  $(error Unknown kernel $(KERNEL), choose SOBEL_X, BOX, GAUSS)
endif

EXTRA_ARGS += +define+KERNEL_TYPE=$(KERNEL_TYPE)


WARNING_ARGS += \
	-Wno-lint \
	-Wno-style \
	-Wno-SYMRSVDWORD \
	-Wno-IGNOREDRETURN \
	-Wno-CONSTRAINTIGN \
	-Wno-ZERODLY \
	-Wno-SELRANGE \
	-Wno-MULTIDRIVEN

.PHONY: gen-txt gen-param all build run clean sim compare download_random_img random_test install

all: sim

install:
	pip3 install -r $(REQUIREMENTS_FILE)

gen-param:
	python3 sw/cli.py gen-params -i $(GEN_PARAM_IMAGE) -f $(HDL_PARAM)

gen-txt: gen-param
	python3 sw/cli.py gen-txt -i $(GEN_PARAM_IMAGE) -o $(PIXELS_FILE)

build: gen-txt
	$(VERILATOR) --cc --exe --main --timing \
		-Mdir $(SIM_DIR) \
		$(COMPILE_ARGS) \
		$(EXTRA_ARGS) \
		$(WARNING_ARGS) \
		$(SV_SOURCE_FILES) \
		$(TB_FILE)

run: build
	$(MAKE) -j$(NPROC) -C $(SIM_DIR) -f $(SIM_NAME).mk
	./$(SIM_DIR)/$(SIM_NAME)

sim: gen-txt
	$(MAKE) gen-txt
	$(MAKE) run
	$(MAKE) compare

compare : $(PIXELS_FILE)
	python3 sw/cli.py compare -i $(GEN_PARAM_IMAGE) \
	                          -f $(OUTPUT_FILE) \
	                          -k $(KERNEL) \
	                          -o $(GOLDEN_FILE)

download_random_img:
	python3 sw/cli.py download-image

random_test:
	$(MAKE) download_random_img
	$(MAKE) GEN_PARAM_IMAGE=$(RANDOM_IMAGE_FILE) sim

clean:
	rm -rf $(SIM_DIR)
