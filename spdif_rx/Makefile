XCC_OPTS= -O3 -g -report -fxscope
XN=xcore_ai_generic_600.xn

all: spdif_rx.xe
	
spdif_rx.xe: spdif_rx.xc
	xcc $(XCC_OPTS) spdif_rx.xc $(XN) -o $@
	
clean:
	del spdif_rx.xe
