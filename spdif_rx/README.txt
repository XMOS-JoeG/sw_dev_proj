New style SPDIF Receiver architecture
Joe Golightly
17/08/2023

The existing spdif receiver code has a few known limitations:
  - Limited tolerance of non ideal signals (inter symbol interference/Duty Cyle Distortion/jitter)
  - Very difficult debug.

A new spdif receiver architecture is proposed which should address these issues and is presented below.

This description is written assuming the reader has a solid understanding of the IEC60958 (S/PDIF) specification.

Port config
-----------

The spdif input is sampled by a buffered 1-bit port with 32 bit transfer size.

Sample Rates
------------

The new receiver will sample the input at the following rates:
100MHz for 176.4 and 192kHz sample rates.
50MHz for 88.2 and 96kHz sample rates.
25MHz for 44.1 and 48kHz sample rates.

These are double the sampling rates used for the existing implementation. These sampling rate clocks are chosen as they can be created easily using the software reference clock block which always runs at 100MHz or divisions of this.

For all intents and purposes the receiver operation is exactly the same across the sample rate multiples, that is to say, operation at 96kHz sample rate sampling at 50MHz is the same as operation at 48kHz sample rate when sampling at 25MHz. So the following description will only describe the 44.1 and 48kHz base rate receivers.

Sampled bits per S/PDIF UI (unit interval).
-------------------------------------------

The UI is the shortest interval of time using in the encoded S/PDIF data stream. Two unit interval bits are used to convey each bit of data sent over the interface. The biphase mark encoding is that if the UI bits are the same, the transmitted bit is a 0, if they differ, the transmitted bit is a 1.

At 48kHz,   1UI = 1/(48000*128) = 162.76ns. We are sampling at 25MHz = 40ns. So we have ~4.07 sampled bits per UI.
At 44.1kHz, 1UI = 1/(44100*128) = 177.15ns. We are sampling at 25MHz = 40ns. So we have ~4.43 sampled bits per UI.

Because both of these values are close to 4, in a 32 bit word we get approximately 32/4 = 8 unit intervals. This is 4 raw data bits.
Each subframe contains 32 raw data bits so this would be contained in ~8 32 bit words.

Now, we need to overcome the issue that, although close to 4, these sampled bit counts are not exactly 4. So over time we would go out of sync. The method to overcome this is to occasionally drop bits such that our average will come back down to 4.

How many bits do we need to drop?
---------------------------------

At 48kHz, our 4 raw data bits (8 UI) occupy ~1302ns this is (1302/40) = 32.552 bits. So we have 0.552 too many sampled bits per 32 bit sample.
At 44.1kHz, our 4 raw data bits (8 UI) occupy ~1417ns this is (1417/40) = 35.430 bits. So we have 3.430 too many sampled bits per 32 bit sample.

How do we drop bits?
--------------------

We use the port timers to time the point at which we collect the next 32 bits.
If we collected data from the port every 32 port clocks then we would never miss any data. We drop a bit by collecting the next word at last_time + 33 for example. We can even move in the other direction and collect the next word at last_time + 31, this will capture the parallel data word from the Serdes before it has filled all 32 bits.


