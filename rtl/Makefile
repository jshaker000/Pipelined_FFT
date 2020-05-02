MODULE_NAME    := fft
VERILATED_NAME := V${MODULE_NAME}
FFT_LEN        ?= 256
OBJ_DIR        := obj_dir_${FFT_LEN}
CFLAGS         := -Wall -O3 --std=c++17
LDLIBS         := -lfftw3
V_FLAGS        := -Wall --assert --clk mclk --trace --Mdir ${OBJ_DIR} --prefix ${VERILATED_NAME} -GFFT_LEN=${FFT_LEN}

.PHONY: default clean

run : all
	${OBJ_DIR}/./${VERILATED_NAME}

all : ${OBJ_DIR}/${VERILATED_NAME}

${OBJ_DIR}/${VERILATED_NAME} : % : %.mk ${MODULE_NAME}.cpp
	cd ${OBJ_DIR}; make -f $(patsubst ${OBJ_DIR}/%,%,$<)
	@ touch $@

${OBJ_DIR}/${VERILATED_NAME}.mk : ${MODULE_NAME}.v $(filter-out ${MODULE_NAME}, *.v) twiddle_rom.v
	verilator ${V_FLAGS} -cc $< --exe $(patsubst %.v,%.cpp,$<) -CFLAGS "${CFLAGS}" -LDFLAGS "${LDLIBS}"
	@ touch $@

twiddle_rom.v: gen_twiddle_v.py
	./$<

clean:
	rm -rf obj_dir* *.vcd twiddle_rom.v
