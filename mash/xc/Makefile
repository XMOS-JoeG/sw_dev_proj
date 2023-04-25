XCC_OPTS = -O2 -g -report
TARGET = XCORE-AI-EXPLORER

all: mash.xe mash_app_pll.xe

mash.xe: mash.xc
	xcc $(XCC_OPTS) mash.xc -target=$(TARGET) -o $@
  
mash_app_pll.xe: mash_app_pll.xc
	xcc $(XCC_OPTS) mash_app_pll.xc -target=$(TARGET) -o $@
	
clean:
	rm mash.xe mash_app_pll.xe
