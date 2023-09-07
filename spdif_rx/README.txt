New style SPDIF Receiver architecture
Joe Golightly
17/08/2023

The existing spdif receiver code has a few known limitations:
  - Limited tolerance of non ideal signals (inter symbol interference/Duty Cyle Distortion/jitter)
  - Very difficult debug.

A new spdif receiver architecture is proposed which should address these issues and is presented below.

This description is written assuming the reader has a solid understanding of the IEC60958 (S/PDIF) specification.

General overview
----------------

The new receiver samples (ideally) in the middle of the second UI (unit interval) for each transmitted bit. By comparing each sample with the last sample we can recover the original data stream. For each sub-frame, we sample these bits 4 at a time and load into a 32 bit value, shifting left by 4 bits each time. At the end of the subframe we have filled the whole 32 bit value so we XOR this value with a version of itself shifted by 1 bit. This achieves the data recovery by xor'ing each sampled bit with the last bit. If the bits were different, the xor output is 1, if they were the same the xor output is 0. If the bits were the same, because of the biphase mark encoding scheme enforcing a transition every transmitted bit then it means there must have been another transition for this bit interval to end up with the same value. Having a transition in the bit interval (2UI) correlates to a transmitted 1. Not having a transition correlates to a transmitted 0. So we can see we need to invert the output of our XOR to get the original transmitted bits in the correct polarity.

The actual sampling of these bits is more complicated. It is achieved essentially by sampling the input much faster than required into a 32 bit value and then using a mask to extract the bits required at the ideal timing point. The mask and timing points are always fixed but the input data stream itself is adjusted in time by selectively dropping bits as required such that a specific transition is always aligned near the middle of the 32 bit word received. This can be seen as a software delay locked loop allowing the receiver to track the input clock rate despite using an asynchronous sampling clock.

Port config
-----------

The spdif input is sampled by a buffered 1-bit port with 32 bit transfer size. The clock used for the buffered port is a divided version of the software reference clock and runs at either 100MHz, 50MHz or 25MHz.

Port data endianness
--------------------

XMOS ports always shift right in their serdes blocks. This means output data is LSB first i.e the earliest bits received will form the LSBs of the output word. This can be confusing when printing data but we just need to remember that the time axis essentially goes from right to left instead of the normal left to right. We do not bitrev the data to save instructions so we keep this arrangement throughout all of the description that follows.

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

Now, we need to overcome the issue that, although close to 4, these sampled bit counts are not exactly 4. So over time we would go out of sync were we to sample continuously. The method to overcome this is to occasionally drop bits such that our average will come back down to 4.

How many bits do we need to drop?
---------------------------------

At 48kHz,   our 4 raw data bits (8 UI) occupy ~1302ns this is (1302/40) = 32.552 bits. So we have 0.552 too many sampled bits per 32 bit sample.
At 44.1kHz, our 4 raw data bits (8 UI) occupy ~1417ns this is (1417/40) = 35.430 bits. So we have 3.430 too many sampled bits per 32 bit sample.

To make sure we stay in sync, we drop some bits by default to get us as close as possible to these values. So for 48kHz, we drop 1 bit per 32 bit sample (collect data after 33 port clocks). For 44.1kHz we drop 3 bits per 32 bit sample (collect data after 35 port clocks).

How do we drop bits?
--------------------

We use the port timers to time the point at which we collect the next 32 bits from the port.

Conceptually, the 1-bit buffered port can be seen as a shift register which runs continuously at the rate of the port clock. What we do is instead of reading the parallel output when it becomes full of data (after 32 port clocks) we alter the time at which we read the parallel output from the shift register so we can either read data early (e.g. after 31 port clocks) or late (e.g. after 33 port clocks). Each time we read early or late we lose some data samples but the system is arranged such that these are never critical to operation of the receiver (they aren't at points in time when we need to collect our input sample).

How do we know when to drop bits?
--------------------------------

For each 32 bit input word, we use a series of instructions to see where a specific transition is in the input word. The transition will always be present due to the biphase mark protocol. We choose the ideal position for this transition as between bits 13 and 14, i.e. bits 13 and 14 are opposite polarity. We pick this position because it means the sampling mask we use (described later) is roughly symmetrical in the 32 bit word. If in the received word the transition was between 14 and 15 instead then we know we sampled one bit too early as the data was one bit too late. We take this value and alter our next read point to be one bit too late to bring us back into line with the transmitted data. In this way we track the clock rate of the transmitted data.

Exact method
Key line is:
error = 18 - cls(sext(sample, 16));
The original sample is first sign extended from bit position 16 - (bit position 15 is copied to all bits higher). This makes sure that the first transition seen (looking from the MSB) is the transition we are interested in (ideally between bits 13 and 14).
We then use the CLS instruction to count the number of bits to the transition. In our ideal case this should be 18 (32-14). So our error (how far we were early/late) is 18 - measured MSB bits to the transition in input sample.
We add this error to the default port time adder mentioned before (33 for 48kHz) so make sure our next transition has the best chance of being where we want.

Note we also use this error to shift the input sample to ensure it has its transition exactly between bits 13 and 14. This is required when we process the sample to extract the encoded SPDIF data.

How do we sample data from received words?
-----------------------------------------

Now we have all the input data in the following format:
 8UI of raw SPDIF data arranged in a 32 bit word where the middle transition (4UI each side) is exactly between bits 13 and 14.

We need to extract four data bits from this 32 bit word. (These are the sample points at 75% of each of four 2UI windows).

The first step is to mask off the four data bits we want. This mask is different for 48kHz and 44.1kHz as the ideal sampling points are at different times.
The ideal sampling point is tricky. We want to sample in the middle of a 1UI interval which corresponds to four sampled bits. So we can sample either of the middle two bits, this should result in the same timing margins.
Our sampling points are ideally separated by 2UI.
For 48kHz this is 32.552/4 bits = 8.138 bits. So if we sample every 8 bits, for our four sampling points, our sampling error will be 
Bit Sampling time error
0   -0.207 bits
1   -0.069 bits
2   +0.069 bits
3   +0.207 bits
This is assuming the error is symmetrical about an ideal point in the middle of the 32 bit word.

For 44.1kHz this is 35.430/4 bits = 8.858 bits. So if we sample every 9 bits, for our four sampling points, our sampling error will be 
Bit Sampling time error
0   -0.213 bits
1   -0.071 bits
2   +0.071 bits
3   +0.213 bits

These errors are small enough that they shouldn't impact the timing margin significantly.

So our masks are chosen as 
Sample rate   Sample Mask
48kHz         0x10101010
44.1kHz       0x40201008

BIT
3322222222221111111111
10987654321098765432109876543210

11000000001111111100000000111111 Example 48kHz input
00010000000100000001000000010000 48kHz Mask

00000000011111111100000000011111 Example 44.1kHz input
01000000001000000001000000001000 44.1kHz Mask

Once we have masked off the bits of interest we use the CRC32 instruction as a hash function to "compress" the data into a 4bit value. This 4bit value does not map directly to the sample data itself but it is unique for each possible input word. So we now need to use an unscrambling lookup function to extract the actual sampled data values.
This is a somewhat complicated process but it is essential to keep the instruction count low.

For each 4 bits recovered we OR these into the top 4 bits of a 32 bit word representing data for the current subframe and then shift this down by 4 bits ready for the next 4 bits to be OR'ed in. This is to ensure the data is output in the correct format.

How do we synchronise to preambles?
-----------------------------------

As part of our software DLL we require a transition every 8UI (four bits). There is only one set of transitions in the SPDIF stream where this is the case and it is the transition at the start of a preamble and every 8UI thereon. Anywhere else in the stream will eventually have a missing transition due to one of the preambles biphase-mark violations.

In order to make detection of preambles possible, the S/PDIF subframe is aligned in our 32 bit input words in the following fashion. A subframe always occupies 8 32 bit words when the DLL is locked.

The subframe format is 32 bits of data in the order (in time left to right)

BIT
          1111111111222222222233
01234567890123456789012345678901

PPPP<0---24 bit sample---23>VUCP

first column is word count. Second column is order of subframe bits in input sample (remember time right to left)

0 - 1  0  31 30
1 - 5  4  3  2
2 - 9  8  7  6
3 - 13 12 11 10
4 - 17 16 15 14
5 - 21 20 19 18
6 - 25 24 23 22
7 - 29 28 27 26
8 - 1  0  31 30
9 - 5  4  3  2
etc ...

This is done because it allows us to use the CLS instruction to spot the long run of bits at the start of a preamble. (Nominally 12 or 13 bits in a row). This is contained in "bits" 0 and 1 of the subframe.

A typical input sample for a preamble would be

BIT
3322222222221111111111
10987654321098765432109876543210

00000011111111111100001111000000

We use a similar command to our edge detector in the DLL.
if (cls(sext(sample, pre_det_point)) > 16)

We sign extend from around bit 24 and then detect if the subsequent word has leading sign bits all the way to the bit 13/14 transition. If it does it is a preamble.
If it was not a preamble, the transition of the 2UI boundary would be present at bit 21/22 so counting the leading sign would yield ~10.


Initial DLL lock to correct transition in input stream
------------------------------------------------------

If we just free run the DLL it will very quickly lock our reference edge to one of two edges in the spdif input stream. Either the edge at the start of a preamble or the edge 3/4 the way through X and Y preambles. If only X and Y preambles are present then this edge also has a transition every 8UI. This edge is not present in Z preambles so when the DLL receives a Z preamble it will correct this but Z preambles are relatively uncommon only occurring every 384 subframes.
To avoid needing to wait for a Z preamble, we have a system to fast lock the DLL to the correct edge (start of preamble). The way this works is if we are locked to the incorrect edge (3/4 the way through preamble) our preamble detection command (described later) will not detect any preambles. Because we know there should be a preamble every 8 input words we can detect if haven't received the expected number of preambles and hence we are locked to the wrong edge. If we detect we are locked to the wrong edge we add 8 to the port counter at which we take the next input. This will delay our input by 2UI of the input data stream which means we should now be locked to the correct edge. (3/4 of preamble to 4/4 of preamble is 2UI).

Z Preamble detection
--------------------

One issue is that although we can detect all preambles easily, it is harder to discern which type of preamble (X,Y or Z) was present. X and Y preambles can be worked out from the decoded output data after the XOR and inversion. Unfortunately due to the location of our sampling points, it is not possible to discern Z preambles from X preambles.

A somewhat brute force method is used currently to detect Z preambles by looking for the long pulse at the end of the preamble that is only present for Z preambles. We then store this as a flag and OR into the output word before outputting to channel.