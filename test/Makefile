# Cocotb test Makefile — runs all test groups across different toplevels
# See https://docs.cocotb.org/en/stable/quickstart.html

SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src

PROJECT_SOURCES = project.v \
    verilog/src/pred.v \
    verilog/src/perceptron.v \
    verilog/src/pred_slave_spi.v \
    verilog/src/ram_interface.v \
    verilog/lib/verilog_spi/spi_module.v \
    verilog/lib/verilog_spi/clock_divider.v \
    verilog/lib/verilog_spi/neg_edge_det.v \
    verilog/lib/verilog_spi/pos_edge_det.v

# Default: run all test groups
.PHONY: all clean test-tt test-wrapper test-ram

all: test-tt test-wrapper

# TT wrapper smoke test (toplevel = tb)
test-tt:
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES)) $(PWD)/tb.v" \
		COMPILE_ARGS="-I$(SRC_DIR)" \
		TOPLEVEL=tb \
		MODULE=test \
		SIM_BUILD=sim_build/tt \
		COCOTB_RESULTS_FILE=results_tt.xml

# Full pred_top tests with RAM model (toplevel = tb_wrapper)
test-wrapper:
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES)) $(PWD)/tb_wrapper.v $(PWD)/models/spi_ram_slave.v" \
		COMPILE_ARGS="-I$(SRC_DIR)" \
		TOPLEVEL=tb_wrapper \
		MODULE=test_prediction,test_update,test_config,test_spi_edge_cases,test_end_to_end \
		SIM_BUILD=sim_build/wrapper \
		COCOTB_RESULTS_FILE=results_wrapper.xml

# RAM interface unit tests (toplevel = ram_interface)
test-ram:
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(addprefix $(SRC_DIR)/,verilog/src/ram_interface.v verilog/lib/verilog_spi/spi_module.v verilog/lib/verilog_spi/clock_divider.v verilog/lib/verilog_spi/neg_edge_det.v verilog/lib/verilog_spi/pos_edge_det.v)" \
		COMPILE_ARGS="-I$(SRC_DIR)" \
		TOPLEVEL=ram_interface \
		MODULE=test_weight_spi \
		SIM_BUILD=sim_build/ram \
		COCOTB_RESULTS_FILE=results_ram.xml

clean:
	rm -rf sim_build results*.xml __pycache__ *.fst
