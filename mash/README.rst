MASH README
###########

This directory has some code and scripts relating to implementation of a MASH delta sigma modulator.

This is primarily going to be used in the secondary PLL in Quake to provide very high frequency accuracy which allows real time adjustment of output frequency to synchrnoise to an external clock. It allows turning the PLL essentially into a DCO (digitally controlled oscillator) with high precision input, around 20 bits.

For the PLL case this modulator is primarily used with a static input (only changing very slightly at the most for tuning). There's no reason it can't be used to modulate a dynamic signal such as audio into a higher bit rate, lower resolution signal.

The specific modulator implemented here is a 3-stage cascaded first order delta sigma modulator known as MASH 1-1-1.

The python directory contains a python model of the modulator. This allows for analysing the output for its behaviour in the time and frequency domain to check it is doing what we want (low noise in low frequencies, rising noise to higher frequencies).

The xc directory contains software implementing the modulator which can run on the xmos device. This allowed proof of concept in writing the PLL divider register with the modulator output to achieve the desired afffect. Downside is this needs a whole thread as it needs to write the divider register very fast. For quake we are putting this modulator in hardware in the device such that this thread will not be needed. Just write a 20 bit value to a register to set the frequency needed.

I've included this code as it might be useful as a generic modulator for producing an analogue output from an xmos device. For example it potentially could be used for modulating audio to drive a PWM output to a half bridge to form a class-D amplifier. Or otherwise it could be used for generic accurate analogue output like an advanced PWM output (once fed through appropriate filtering and buffering).
