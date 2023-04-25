MASH Modulator in XC
####################

mash.xc shows an xc implementation of a 20 bit MASH 1-1-1 modulator.

This is mostly a proof of concept and for verifying accuracy of the implementation. The output of the modulator can be compared with that produced by the python model for equivalency.

Build and run using xmake and then xsim mash.xe. Or run on real hardware with xrun --io mash.xe.

This code has been used for programming the secondary PLL feedback divider register in real time to allow very fine frequency accuracy. This has been included as mash_app_pll.xc.
This will produce varying frequency on the secondary PLL output pin for a given 20 bit value set in the program. Run on an xcore.ai explorer board or stereo usb audio board.
