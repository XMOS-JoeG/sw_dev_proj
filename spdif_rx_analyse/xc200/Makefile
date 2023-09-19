XCC_OPTS= -O2 -g -report
XN=XR-AUDIO-216-MC.xn

all: spdif_rx_analyse.xe

spdif_rx_analyse.xe: ../spdif_rx_analyse.xc
	xcc $(XCC_OPTS) -D TILE=1 -D XC200 ../spdif_rx_analyse.xc $(XN) -o $@
	
clean:
	rm spdif_rx_analyse.xe
