XCC_OPTS= -O2 -g -report
XN=xcore_ai_generic_800.xn

all: spdif_rx_analyse.xe

spdif_rx_analyse.xe: spdif_rx_analyse.xc
	xcc $(XCC_OPTS) spdif_rx_analyse.xc $(XN) -o $@
	
clean:
	rm spdif_rx_analyse.xe
