XCC_OPTS= -O2 -g -report
XN=xcore_ai_generic_500.xn

all: spdif_rx_analyse.xe

spdif_rx_analyse.xe: spdif_rx_analyse.xc
	xcc $(XCC_OPTS) -D TILE=0 spdif_rx_analyse.xc $(XN) -o $@
	
clean:
	rm spdif_rx_analyse.xe
