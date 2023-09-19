XCC_OPTS= -O3 -g -report -fxscope
XN=XR-AUDIO-216-MC.xn

all: spdif_rx.xe
	
spdif_rx.xe: ../spdif_rx.xc
	xcc $(XCC_OPTS) -D TILE=1 -D XC200 ../spdif_rx.xc $(XN) -o $@
	
clean:
	del spdif_rx.xe
