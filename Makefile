TOPLEVEL ?= mkTestGenericArbiter
TEST_MODULE ?= test_generic_arbiter
BSV_FILE ?= test/bsv/TestRouting.bsv
BSC_DEFINES ?=
AXI_MUX_TEST_PORTS ?= 1 3 8
AXI_MUX_TEST_DEPTHS ?= 1 2 3 8
AXI_MUX_TEST_FALL_THROUGH ?= 0 1
AXI_MUX_TEST_ONEHOT0 ?= 0

BUILD_DIR := build/$(TOPLEVEL)
BSC_DIR := $(BUILD_DIR)/bsc
SIM_DIR := $(BUILD_DIR)/sim
BLUESIM_BINARY := $(BUILD_DIR)/$(TOPLEVEL)
# Bluesim's bs_prim_mod_reg.h triggers GCC warnings for its VCD port-name buffers.
BLUESIM_CXXFLAGS ?= -Wno-format-truncation
VERILOG_DIR := $(BUILD_DIR)/verilog
COCOTB_MAKEFILE := $(shell cocotb-config --makefiles)/Makefile.sim
BLUESPEC_VERILOG := $(shell dirname $$(dirname $$(command -v bsc)))/lib/Verilog

export PYTHONPATH := $(CURDIR)/test/cocotb:$(PYTHONPATH)
COCOTB_LOG_LEVEL ?= WARNING
export COCOTB_LOG_LEVEL

SOC_MAP_BUILD_DIR ?= build/mkTestSocMaps
ADDR_MAP_BUS_BUILD_DIR ?= build/mkTestAddrMapBus

.PHONY: test-connections
.PHONY: test-soc-maps test-addr-map-bus test-addr-map-decoder
.PHONY: test-apb-slave test-apb-slave-bypass test-apb-master test-apb-mux test-apb-master-mux
.PHONY: test-axi-lite-mux test-axi-lite-mux-fabric test-axi-lite-reg-slice
.PHONY: test-ahb-slave test-ahb-slave-bypass test-ahb-master test-ahb-mux test-ahb-master-mux test-ahb-apb-bridge
.PHONY: bluesim

test: test-connections
test: test-soc-maps
test: test-addr-map-bus
test: test-addr-map-decoder
test: test-arbiter
test: test-apb-slave test-apb-slave-bypass test-apb-master
test: test-apb-mux test-apb-master-mux
test: test-axi-lite-mux test-axi-lite-reg-slice
test: test-ahb-slave test-ahb-slave-bypass test-ahb-master test-ahb-mux test-ahb-master-mux
test: test-ahb-apb-bridge

test-connections:
	$(MAKE) TOPLEVEL=mkTestConnections \
		BSV_FILE=test/bsv/TestConnections.bsv verilog

test-soc-maps:
	mkdir -p $(SOC_MAP_BUILD_DIR)/bsc $(SOC_MAP_BUILD_DIR)/sim
	bsc -u -sim -g mkTestSocMaps \
		-bdir $(SOC_MAP_BUILD_DIR)/bsc \
		-simdir $(SOC_MAP_BUILD_DIR)/sim \
		-p +:src:src/apb:src/axi:src/axi/blueaxi/src:src/ahb:src/common:src/soc:test/bsv \
		test/bsv/TestSocMaps.bsv
	bsc -sim -e mkTestSocMaps \
		-bdir $(SOC_MAP_BUILD_DIR)/bsc \
		-simdir $(SOC_MAP_BUILD_DIR)/sim \
		-o $(SOC_MAP_BUILD_DIR)/test_soc_maps
	$(SOC_MAP_BUILD_DIR)/test_soc_maps

test-addr-map-bus:
	mkdir -p $(ADDR_MAP_BUS_BUILD_DIR)/bsc $(ADDR_MAP_BUS_BUILD_DIR)/sim
	bsc -u -sim -g mkTestAddrMapBus \
		-bdir $(ADDR_MAP_BUS_BUILD_DIR)/bsc \
		-simdir $(ADDR_MAP_BUS_BUILD_DIR)/sim \
		-p +:src:src/apb:src/axi:src/axi/blueaxi/src:src/ahb:src/common:src/soc:test/bsv \
		test/bsv/TestAddrMapBus.bsv
	bsc -sim -e mkTestAddrMapBus \
		-bdir $(ADDR_MAP_BUS_BUILD_DIR)/bsc \
		-simdir $(ADDR_MAP_BUS_BUILD_DIR)/sim \
		-o $(ADDR_MAP_BUS_BUILD_DIR)/test_addr_map_bus
	$(ADDR_MAP_BUS_BUILD_DIR)/test_addr_map_bus

test-addr-map-decoder:
	$(MAKE) TOPLEVEL=mkTestAddrMapDecoder \
		BSV_FILE=test/bsv/TestAddrMapDecoder.bsv \
		TEST_MODULE=test_addr_map_decoder run
	python3 test/scripts/check_addr_map_validation.py

test-arbiter:
	$(MAKE) TOPLEVEL=mkTestGenericArbiter \
		BSV_FILE=test/bsv/TestRouting.bsv \
		TEST_MODULE=test_generic_arbiter run

test-apb-slave:
	$(MAKE) TOPLEVEL=mkTestApbSlave \
		BSV_FILE=test/bsv/TestApb.bsv \
		TEST_MODULE=test_apb_slave run

test-apb-slave-bypass:
	$(MAKE) TOPLEVEL=mkTestApbSlaveBypass \
		BSV_FILE=test/bsv/TestApb.bsv \
		TEST_MODULE=test_apb_slave run

test-apb-master:
	$(MAKE) TOPLEVEL=mkTestApbMaster \
		BSV_FILE=test/bsv/TestApb.bsv \
		TEST_MODULE=test_apb_master run

test-apb-mux:
	$(MAKE) TOPLEVEL=mkTestApbSlaveMux \
		BSV_FILE=test/bsv/TestBusMux.bsv \
		TEST_MODULE=test_apb_slave_mux run

test-apb-master-mux:
	$(MAKE) TOPLEVEL=mkTestApbMasterMux \
		BSV_FILE=test/bsv/TestBusMux.bsv \
		TEST_MODULE=test_apb_master_mux run

test-axi-full2lite:
	$(MAKE) TOPLEVEL=mkTestAxi4Full2Lite \
		BSV_FILE=test/bsv/TestAxi4Full2Lite.bsv \
		TEST_MODULE=test_axi4_full2lite bluesim

test-axi-lite-mux:
	$(MAKE) TOPLEVEL=mkTestAxi4LiteMux \
		BSV_FILE=test/bsv/TestAxi4LiteMux.bsv \
		TEST_MODULE=test_axi4_lite_mux run
	$(MAKE) test-axi-lite-mux-fabric
	# sel_onehot0 only removes the multi-hot check; a reduced matrix covers it.
	$(MAKE) test-axi-lite-mux-fabric AXI_MUX_TEST_ONEHOT0=1 AXI_MUX_TEST_PORTS="3 8" AXI_MUX_TEST_DEPTHS="1 3"

test-axi-lite-mux-fabric:
	@set -e; for onehot in $(AXI_MUX_TEST_ONEHOT0); do \
		for fall in $(AXI_MUX_TEST_FALL_THROUGH); do \
			for ports in $(AXI_MUX_TEST_PORTS); do \
				for depth in $(AXI_MUX_TEST_DEPTHS); do \
					suffix=$$( [ $$onehot = 1 ] && echo -o1 || true ); \
					AXI_MUX_TEST_DEPTH=$$depth AXI_MUX_TEST_FALL_THROUGH=$$fall AXI_MUX_TEST_ONEHOT0=$$onehot \
					$(MAKE) TOPLEVEL=mkTestAxi4LiteFabric \
						BSV_FILE=test/bsv/TestAxi4LiteFabric.bsv \
						TEST_MODULE=test_axi4_lite_fabric \
						BUILD_DIR=build/mkTestAxi4LiteFabric-p$$ports-d$$depth-f$$fall$$suffix \
						BSC_DEFINES="-D AXI_MUX_PORTS=$$ports -D AXI_MUX_DEPTH=$$depth -D AXI_MUX_FALL_THROUGH=$$fall -D AXI_MUX_ONEHOT0=$$onehot" run; \
				done; \
			done; \
		done; \
	done

# Every channel registered, request channels only, and pure pass-through.
test-axi-lite-reg-slice:
	@set -e; for cfg in 2 1 0; do \
		REG_SLICE_TEST_CFG=$$cfg $(MAKE) TOPLEVEL=mkTestAxi4LiteRegSlice \
			BSV_FILE=test/bsv/TestAxi4LiteRegSlice.bsv \
			TEST_MODULE=test_axi4_lite_reg_slice \
			BUILD_DIR=build/mkTestAxi4LiteRegSlice-c$$cfg \
			BSC_DEFINES="-D REG_SLICE_CFG=$$cfg" run; \
	done

test-ahb-slave:
	$(MAKE) TOPLEVEL=mkTestAhbSlave \
		BSV_FILE=test/bsv/TestAhb.bsv \
		TEST_MODULE=test_ahb_slave run

test-ahb-slave-bypass:
	$(MAKE) TOPLEVEL=mkTestAhbSlaveBypass \
		BSV_FILE=test/bsv/TestAhb.bsv \
		TEST_MODULE=test_ahb_slave run

test-ahb-master:
	$(MAKE) TOPLEVEL=mkTestAhbMaster \
		BSV_FILE=test/bsv/TestAhb.bsv \
		TEST_MODULE=test_ahb_master run

test-ahb-mux:
	$(MAKE) TOPLEVEL=mkTestAhbSlaveMux \
		BSV_FILE=test/bsv/TestBusMux.bsv \
		TEST_MODULE=test_ahb_slave_mux run

test-ahb-master-mux:
	$(MAKE) TOPLEVEL=mkTestAhbMasterMux \
		BSV_FILE=test/bsv/TestBusMux.bsv \
		TEST_MODULE=test_ahb_master_mux run

test-ahb-apb-bridge:
	$(MAKE) TOPLEVEL=mkTestAhbApbBridge \
		BSV_FILE=test/bsv/TestAhbApbBridge.bsv \
		TEST_MODULE=test_ahb_apb_bridge run

.PHONY: run
run: verilog
	$(MAKE) -f $(COCOTB_MAKEFILE) \
		SIM=icarus \
		TOPLEVEL_LANG=verilog \
		TOPLEVEL=$(TOPLEVEL) \
		MODULE=$(TEST_MODULE) \
		COCOTB_TEST_MODULES=$(TEST_MODULE) \
		VERILOG_SOURCES="test/cocotb/timescale.v $(wildcard $(VERILOG_DIR)/*.v)" \
		COMPILE_ARGS="-y $(BLUESPEC_VERILOG)" \
		SIM_BUILD=$(BUILD_DIR)/sim \
		COCOTB_RESULTS_FILE=$(BUILD_DIR)/results.xml
	python3 -c 'import xml.etree.ElementTree as E; r = E.parse("$(BUILD_DIR)/results.xml"); assert r.findall(".//testcase") and not r.findall(".//failure") and not r.findall(".//error"), "Simulation failed: $(BUILD_DIR)/results.xml"'

bluesim:
	mkdir -p $(BSC_DIR) $(SIM_DIR)
	bsc -u -sim -g $(TOPLEVEL) \
		$(BSC_DEFINES) \
		-D BSV_TIMESCALE=1ns/1ps \
		-aggressive-conditions \
		-bdir $(BSC_DIR) \
		-simdir $(SIM_DIR) \
		-p +:src:src/apb:src/axi:src/axi/blueaxi/src:src/ahb:src/common:src/soc:test/bsv \
		$(BSV_FILE)
	bsc -sim -e $(TOPLEVEL) \
		$(foreach flag,$(BLUESIM_CXXFLAGS),-Xc++ $(flag)) \
		-bdir $(BSC_DIR) \
		-simdir $(SIM_DIR) \
		-o $(BLUESIM_BINARY)
	$(BLUESIM_BINARY) -V $(SIM_DIR)/dump.vcd

verilog:
	mkdir -p $(BSC_DIR) $(VERILOG_DIR)
	bsc -u -verilog -g $(TOPLEVEL) \
		$(BSC_DEFINES) \
		-D BSV_TIMESCALE=1ns/1ps \
		-bdir $(BSC_DIR) \
		-vdir $(VERILOG_DIR) \
		-p +:src:src/apb:src/axi:src/axi/blueaxi/src:src/ahb:src/common:src/soc:test/bsv \
		$(BSV_FILE)

clean:
	rm -rf build sim_build results.xml
