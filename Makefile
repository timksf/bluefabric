TOPLEVEL ?= mkTestAxiStreamRegister
TEST_MODULE ?= test_axis_stream_buffers
BSV_FILE ?= test/TestAxiStreamBuffers.bsv

BUILD_DIR := build/$(TOPLEVEL)
BSC_DIR := $(BUILD_DIR)/bsc
VERILOG_DIR := $(BUILD_DIR)/verilog
COCOTB_MAKEFILE := $(shell cocotb-config --makefiles)/Makefile.sim
BLUESPEC_VERILOG := $(shell dirname $$(dirname $$(command -v bsc)))/lib/Verilog

export PYTHONPATH := $(CURDIR)/test:$(PYTHONPATH)
COCOTB_LOG_LEVEL ?= WARNING
export COCOTB_LOG_LEVEL

SOC_MAP_BUILD_DIR ?= build/mkTestSocMaps

.PHONY: test test-register test-register-minimal test-fifo test-async-fifo
.PHONY: test-connections
.PHONY: test-soc-maps
.PHONY: test-up-converter
.PHONY: test-down-converter test-compactor verilog clean
.PHONY: test-arbiter test-mux test-demux test-crossbar
.PHONY: test-apb-slave test-apb-slave-bypass test-apb-master test-apb-mux test-apb-master-mux
.PHONY: test-axi-lite-mux
.PHONY: test-ahb-slave test-ahb-slave-bypass test-ahb-master test-ahb-mux test-ahb-master-mux test-ahb-apb-bridge
.PHONY: test-gate test-snooper test-skid-buffer
.PHONY: test-broadcast test-split test-join
.PHONY: test-interleaver test-remap
.PHONY: test-switch-1to2 test-switch-2to1
.PHONY: test-switch-1to2-unlocked test-switch-2to1-unlocked

test: test-register test-register-minimal test-fifo test-async-fifo
test: test-connections
test: test-soc-maps
test: test-up-converter
test: test-down-converter test-compactor
test: test-arbiter test-mux test-demux test-crossbar
test: test-apb-slave test-apb-slave-bypass test-apb-master
test: test-apb-mux test-apb-master-mux
test: test-axi-lite-mux
test: test-ahb-slave test-ahb-slave-bypass test-ahb-master test-ahb-mux test-ahb-master-mux
test: test-ahb-apb-bridge
test: test-gate test-snooper test-skid-buffer
test: test-broadcast test-split test-join
test: test-interleaver test-remap
test: test-switch-1to2 test-switch-2to1
test: test-switch-1to2-unlocked test-switch-2to1-unlocked

test-register:
	$(MAKE) TOPLEVEL=mkTestAxiStreamRegister run

test-register-minimal:
	$(MAKE) TOPLEVEL=mkTestAxiStreamRegisterMinimal run

test-fifo:
	$(MAKE) TOPLEVEL=mkTestAxiStreamFifo run

test-connections:
	$(MAKE) TOPLEVEL=mkTestConnections \
		BSV_FILE=test/TestConnections.bsv verilog

test-soc-maps:
	mkdir -p $(SOC_MAP_BUILD_DIR)/bsc $(SOC_MAP_BUILD_DIR)/sim
	bsc -u -sim -g mkTestSocMaps \
		-bdir $(SOC_MAP_BUILD_DIR)/bsc \
		-simdir $(SOC_MAP_BUILD_DIR)/sim \
		-p +:src:src/axis:src/apb:src/axi:src/axi/blueaxi/src:src/ahb:src/common:src/soc:test \
		test/TestSocMaps.bsv
	bsc -sim -e mkTestSocMaps \
		-bdir $(SOC_MAP_BUILD_DIR)/bsc \
		-simdir $(SOC_MAP_BUILD_DIR)/sim \
		-o $(SOC_MAP_BUILD_DIR)/test_soc_maps
	$(SOC_MAP_BUILD_DIR)/test_soc_maps

test-async-fifo:
	$(MAKE) TOPLEVEL=mkTestAxiStreamAsyncFifo run

test-up-converter:
	$(MAKE) TOPLEVEL=mkTestAxiStreamUp \
		BSV_FILE=test/TestAxiStreamConverters.bsv \
		TEST_MODULE=test_axis_stream_converters run

test-down-converter:
	$(MAKE) TOPLEVEL=mkTestAxiStreamDown \
		BSV_FILE=test/TestAxiStreamConverters.bsv \
		TEST_MODULE=test_axis_stream_converters run

test-compactor:
	$(MAKE) TOPLEVEL=mkTestAxiStreamCompactor \
		BSV_FILE=test/TestAxiStreamConverters.bsv \
		TEST_MODULE=test_axis_stream_converters run

test-arbiter:
	$(MAKE) TOPLEVEL=mkTestGenericArbiter \
		BSV_FILE=test/TestRouting.bsv \
		TEST_MODULE=test_generic_arbiter run

test-mux:
	$(MAKE) TOPLEVEL=mkTestAxiStreamMux \
		BSV_FILE=test/TestRouting.bsv \
		TEST_MODULE=test_axis_stream_routing run

test-demux:
	$(MAKE) TOPLEVEL=mkTestAxiStreamDemux \
		BSV_FILE=test/TestRouting.bsv \
		TEST_MODULE=test_axis_stream_routing run

test-crossbar:
	$(MAKE) TOPLEVEL=mkTestAxiStreamCrossbar \
		BSV_FILE=test/TestRouting.bsv \
		TEST_MODULE=test_axis_stream_routing run

test-apb-slave:
	$(MAKE) TOPLEVEL=mkTestApbSlave \
		BSV_FILE=test/TestApb.bsv \
		TEST_MODULE=test_apb run

test-apb-slave-bypass:
	$(MAKE) TOPLEVEL=mkTestApbSlaveBypass \
		BSV_FILE=test/TestApb.bsv \
		TEST_MODULE=test_apb run

test-apb-master:
	$(MAKE) TOPLEVEL=mkTestApbMaster \
		BSV_FILE=test/TestApb.bsv \
		TEST_MODULE=test_apb run

test-apb-mux:
	$(MAKE) TOPLEVEL=mkTestApbSlaveMux \
		BSV_FILE=test/TestBusMux.bsv \
		TEST_MODULE=test_bus_mux run

test-apb-master-mux:
	$(MAKE) TOPLEVEL=mkTestApbMasterMux \
		BSV_FILE=test/TestBusMux.bsv \
		TEST_MODULE=test_bus_mux run

test-axi-lite-mux:
	$(MAKE) TOPLEVEL=mkTestAxi4LiteMux \
		BSV_FILE=test/TestAxi4LiteMux.bsv \
		TEST_MODULE=test_axi4_lite_mux run

test-ahb-slave:
	$(MAKE) TOPLEVEL=mkTestAhbSlave \
		BSV_FILE=test/TestAhb.bsv \
		TEST_MODULE=test_ahb run

test-ahb-slave-bypass:
	$(MAKE) TOPLEVEL=mkTestAhbSlaveBypass \
		BSV_FILE=test/TestAhb.bsv \
		TEST_MODULE=test_ahb run

test-ahb-master:
	$(MAKE) TOPLEVEL=mkTestAhbMaster \
		BSV_FILE=test/TestAhb.bsv \
		TEST_MODULE=test_ahb run

test-ahb-mux:
	$(MAKE) TOPLEVEL=mkTestAhbSlaveMux \
		BSV_FILE=test/TestBusMux.bsv \
		TEST_MODULE=test_bus_mux run

test-ahb-master-mux:
	$(MAKE) TOPLEVEL=mkTestAhbMasterMux \
		BSV_FILE=test/TestBusMux.bsv \
		TEST_MODULE=test_bus_mux run

test-ahb-apb-bridge:
	$(MAKE) TOPLEVEL=mkTestAhbApbBridge \
		BSV_FILE=test/TestAhbApbBridge.bsv \
		TEST_MODULE=test_ahb_apb_bridge run

test-gate:
	$(MAKE) TOPLEVEL=mkTestAxiStreamGate \
		BSV_FILE=test/TestAxiStreamExtras.bsv \
		TEST_MODULE=test_axis_stream_control run

test-snooper:
	$(MAKE) TOPLEVEL=mkTestAxiStreamSnooper \
		BSV_FILE=test/TestAxiStreamExtras.bsv \
		TEST_MODULE=test_axis_stream_control run

test-skid-buffer:
	$(MAKE) TOPLEVEL=mkTestAxiStreamSkidBuffer \
		BSV_FILE=test/TestAxiStreamExtras.bsv \
		TEST_MODULE=test_axis_stream_control run

test-broadcast:
	$(MAKE) TOPLEVEL=mkTestAxiStreamBroadcast \
		BSV_FILE=test/TestAxiStreamExtras.bsv \
		TEST_MODULE=test_axis_stream_fanout run

test-split:
	$(MAKE) TOPLEVEL=mkTestAxiStreamSplit \
		BSV_FILE=test/TestAxiStreamExtras.bsv \
		TEST_MODULE=test_axis_stream_fanout run

test-join:
	$(MAKE) TOPLEVEL=mkTestAxiStreamJoin \
		BSV_FILE=test/TestAxiStreamExtras.bsv \
		TEST_MODULE=test_axis_stream_fanout run

test-interleaver:
	$(MAKE) TOPLEVEL=mkTestAxiStreamInterleaver \
		BSV_FILE=test/TestAxiStreamExtras.bsv \
		TEST_MODULE=test_axis_stream_route_extras run

test-remap:
	$(MAKE) TOPLEVEL=mkTestAxiStreamRemap \
		BSV_FILE=test/TestAxiStreamExtras.bsv \
		TEST_MODULE=test_axis_stream_route_extras run

test-switch-1to2:
	$(MAKE) TOPLEVEL=mkTestAxiStreamSwitch1To2 \
		BSV_FILE=test/TestAxiStreamExtras.bsv \
		TEST_MODULE=test_axis_stream_route_extras run

test-switch-2to1:
	$(MAKE) TOPLEVEL=mkTestAxiStreamSwitch2To1 \
		BSV_FILE=test/TestAxiStreamExtras.bsv \
		TEST_MODULE=test_axis_stream_route_extras run

test-switch-1to2-unlocked:
	$(MAKE) TOPLEVEL=mkTestAxiStreamSwitch1To2Unlocked \
		BSV_FILE=test/TestAxiStreamExtras.bsv \
		TEST_MODULE=test_axis_stream_route_extras run

test-switch-2to1-unlocked:
	$(MAKE) TOPLEVEL=mkTestAxiStreamSwitch2To1Unlocked \
		BSV_FILE=test/TestAxiStreamExtras.bsv \
		TEST_MODULE=test_axis_stream_route_extras run

.PHONY: run
run: verilog
	$(MAKE) -f $(COCOTB_MAKEFILE) \
		SIM=icarus \
		TOPLEVEL_LANG=verilog \
		TOPLEVEL=$(TOPLEVEL) \
		MODULE=$(TEST_MODULE) \
		COCOTB_TEST_MODULES=$(TEST_MODULE) \
		VERILOG_SOURCES="test/timescale.v $(wildcard $(VERILOG_DIR)/*.v)" \
		COMPILE_ARGS="-y $(BLUESPEC_VERILOG)" \
		SIM_BUILD=$(BUILD_DIR)/sim \
		COCOTB_RESULTS_FILE=$(BUILD_DIR)/results.xml

verilog:
	mkdir -p $(BSC_DIR) $(VERILOG_DIR)
	bsc -u -verilog -g $(TOPLEVEL) \
		-D BSV_TIMESCALE=1ns/1ps \
		-bdir $(BSC_DIR) \
		-vdir $(VERILOG_DIR) \
		-p +:src:src/axis:src/apb:src/axi:src/axi/blueaxi/src:src/ahb:src/common:src/soc:test \
		$(BSV_FILE)

clean:
	rm -rf build sim_build results.xml
