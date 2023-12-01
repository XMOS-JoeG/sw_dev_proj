This program is designed for the xcore.ai mc audio board.

It outputs an spdif stream with the samples synchronised to the channel status block start. This makes it easier to check if samples are correct on the receive side.

Channel 1 (left)  has one full scale sine period over 96 samples.
Channel 2 (right) has two full scale sine period over 96 samples.

This will result in the following frequency sine waves being played at each sample rate:

SR    Freq Ch1  Freq Ch2
32    333Hz     666Hz
44.1  459Hz     919Hz
48    500Hz     1kHz
88.2  919Hz     1.84kHz
96    1kHz      2kHz
176.4 1.84kHz   3.67kHz
192   2kHz      4kHz

The sample frequency can be changed in the sequence 32 - 44.1 - 48 - 88.2 - 96 - 176.4 - 192kHz by pressing Button 0.

The LEDs indicate the current sample rate. The LEDs should be read as a 4 bit binary value (LED0 = LSB).

LED Value   SR (kHz)
1           32
2           44.1 
3           48   
4           88.2 
5           96   
6           176.4
7           192  
