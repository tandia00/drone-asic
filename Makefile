# SAHEL-1 — Makefile principal
# Cibles principales : sim, sim-soc, sim-pwm, sim-ndvi, sim-aes, lint,
#                     harden, harden-wrapper, tarball, clean

PROJECT       ?= drone-asic
TOP           ?= agri_drone_soc
RTL_DIR       := rtl
TB_DIR        := tb
BUILD         := build
OPENLANE_TAG  ?= 2024.04.22
OPENLANE_DIR  ?= $(HOME)/OpenLane

RTL := \
  $(RTL_DIR)/wb_intercon.v \
  $(RTL_DIR)/uart.v \
  $(RTL_DIR)/i2c_master.v \
  $(RTL_DIR)/spi_master.v \
  $(RTL_DIR)/pwm.v \
  $(RTL_DIR)/gpio.v \
  $(RTL_DIR)/timer.v \
  $(RTL_DIR)/aes128.v \
  $(RTL_DIR)/ndvi_accel.v \
  $(RTL_DIR)/sram_wrap.v \
  $(RTL_DIR)/agri_drone_soc.v

IVERILOG ?= iverilog
VVP      ?= vvp
GTKWAVE  ?= gtkwave

# -----------------------------------------------------------------------------
# Simulation Icarus (modules unitaires)
# -----------------------------------------------------------------------------
.PHONY: sim sim-pwm sim-ndvi sim-aes sim-uart wave lint clean harden tarball

sim: sim-pwm sim-ndvi sim-aes sim-uart

$(BUILD):
	mkdir -p $(BUILD)

sim-pwm: | $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/tb_pwm.vvp $(RTL_DIR)/pwm.v $(TB_DIR)/tb_pwm.v
	$(VVP) $(BUILD)/tb_pwm.vvp

sim-ndvi: | $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/tb_ndvi.vvp $(RTL_DIR)/ndvi_accel.v $(TB_DIR)/tb_ndvi.v
	$(VVP) $(BUILD)/tb_ndvi.vvp

SECWORKS_AES := \
  ext/secworks-aes/src/rtl/aes_core.v \
  ext/secworks-aes/src/rtl/aes_encipher_block.v \
  ext/secworks-aes/src/rtl/aes_decipher_block.v \
  ext/secworks-aes/src/rtl/aes_key_mem.v \
  ext/secworks-aes/src/rtl/aes_sbox.v \
  ext/secworks-aes/src/rtl/aes_inv_sbox.v

sim-aes: | $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/tb_aes.vvp $(RTL_DIR)/aes128.v $(SECWORKS_AES) $(TB_DIR)/tb_aes.v
	$(VVP) $(BUILD)/tb_aes.vvp

sim-uart: | $(BUILD)
	$(IVERILOG) -g2012 -o $(BUILD)/tb_uart.vvp $(RTL_DIR)/uart.v $(TB_DIR)/tb_uart.v
	$(VVP) $(BUILD)/tb_uart.vvp

wave:
	$(GTKWAVE) $(BUILD)/$(WAVE).vcd &

# -----------------------------------------------------------------------------
# Lint (Verilator)
# -----------------------------------------------------------------------------
lint:
	verilator --lint-only -Wall -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME \
	    -Wno-PINCONNECTEMPTY -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
	    -Wno-PROCASSINIT -Wno-BLKSEQ -Wno-GENUNNAMED \
	    -Wno-PINMISSING -Wno-TIMESCALEMOD \
	    -Wno-SYNCASYNCNET -Wno-UNOPTFLAT \
	    --top-module agri_drone_soc \
	    -Iext/picorv32 -Iext/secworks-aes/src/rtl \
	    $(RTL) ext/picorv32/picorv32.v $(SECWORKS_AES)

# -----------------------------------------------------------------------------
# OpenLane — synthèse + place&route → GDSII
# -----------------------------------------------------------------------------
harden:
	@if [ ! -d "$(OPENLANE_DIR)" ]; then \
	  echo "ERREUR : OpenLane non trouvé à $(OPENLANE_DIR)"; \
	  echo "Cloner : git clone https://github.com/The-OpenROAD-Project/OpenLane $(OPENLANE_DIR)"; \
	  exit 1; \
	fi
	cd $(OPENLANE_DIR) && \
	  make mount DESIGN_DIR=$(CURDIR)/openlane/$(TOP) \
	             RUN_TAG=sahel1 \
	             docker_command="flow.tcl -design $(CURDIR)/openlane/$(TOP) -run_path $(CURDIR)/runs -tag sahel1"

harden-wrapper:
	cd $(OPENLANE_DIR) && \
	  make mount DESIGN_DIR=$(CURDIR)/openlane/user_project_wrapper \
	             RUN_TAG=sahel1_wrap

# -----------------------------------------------------------------------------
# Empaquetage pour soumission eFabless
# -----------------------------------------------------------------------------
tarball:
	mkdir -p submission
	tar czf submission/sahel1-$$(date +%Y%m%d).tar.gz \
	    info.yaml README.md LICENSE rtl/ openlane/ docs/ firmware/
	@echo "→ submission/sahel1-$$(date +%Y%m%d).tar.gz"

clean:
	rm -rf $(BUILD) runs submission

# -----------------------------------------------------------------------------
# Submodules
# -----------------------------------------------------------------------------
.PHONY: deps
deps:
	@mkdir -p ext
	@if [ ! -d ext/picorv32 ]; then \
	  (cd ext && git clone --depth 1 https://github.com/YosysHQ/picorv32.git); \
	fi
	@if [ ! -d ext/secworks-aes ]; then \
	  (cd ext && git clone --depth 1 https://github.com/secworks/aes.git secworks-aes); \
	fi
