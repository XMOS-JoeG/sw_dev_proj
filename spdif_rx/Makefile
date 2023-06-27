XCC_OPTS= -O2 -g -report -fxscope
XN=xcore_ai_generic_800.xn

all: spdif_rx.xe
	
spdif_rx.xe: spdif_rx.xc
	xcc $(XCC_OPTS) spdif_rx.xc $(XN) -o $@
	
clean:
	rm spdif_rx.xe
