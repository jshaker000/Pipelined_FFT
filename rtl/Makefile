MODULE_NAME    := fft
VERILATED_NAME := V${MODULE_NAME}
FFT_LEN        ?= 256
OBJ_DIR        := obj_dir
CFLAGS         := -Wall -O3 --std=c++17
LDLIBS         := -lfftw3
V_FLAGS        := -Wall --clk mclk --trace --Mdir ${OBJ_DIR} --prefix ${VERILATED_NAME} -GLEN=${FFT_LEN}

.PHONY: default clean

run : all
	${OBJ_DIR}/./${VERILATED_NAME}

all : ${OBJ_DIR}/${VERILATED_NAME}

${OBJ_DIR}/${VERILATED_NAME} : % : %.mk ${MODULE_NAME}.cpp
	cd ${OBJ_DIR}; make -f $(patsubst ${OBJ_DIR}/%,%,$<)

${OBJ_DIR}/${VERILATED_NAME}.mk : ${MODULE_NAME}.v $(filter-out ${MODULE_NAME}, *.v) ${MODULE_NAME}.cpp twiddle_rom.v .${FFT_LEN}.currently_built_fft
	verilator ${V_FLAGS} -cc $< --exe $(patsubst %.v,%.cpp,$<) -CFLAGS "${CFLAGS}" -LDFLAGS "${LDLIBS}"

twiddle_rom.v: gen_twiddle_v.py
	./$<

.%.currently_built_fft:
	@rm -rf .*.currently_built_fft
	@touch $@

clean:
	rm -rf ${OBJ_DIR} *.vcd twiddle_master.v .*.currently_built_fft
