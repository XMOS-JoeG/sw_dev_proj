XCC_OPTS= -O3 -g -report
XN=XCORE-AI-MCAUDIO-600.xn

all: spdif_tx.xe
	
spdif_tx.xe: spdif_tx.xc
	xcc $(XCC_OPTS) spdif_tx.xc xassert.xc SpdifTransmit.xc $(XN) -o $@
	
clean:
	del spdif_tx.xe
