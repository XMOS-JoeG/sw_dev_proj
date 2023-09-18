This program is designed for the xcore.ai mc audio board.

It outputs an spdif stream with the samples synchronised to the channel status block start. This makes it easier to check if samples are correct on the receive side.

Channel 1 (left)  has one full scale sine period over 96 samples.
Channel 2 (right) has two full scale sine period over 96 samples.

This will result in the following frequency sine waves being played at each sample rate:

SR    Freq Ch1  Freq Ch2
44.1  459Hz     919Hz
48    500Hz     1kHz
88.2  919Hz     1.84kHz
96    1kHz      2kHz
176.4 1.84kHz   3.67kHz
192   2kHz      4kHz

The sample frequency can be changed in the sequence 44.1 - 48 - 88.2 - 96 - 176.4 - 192kHz by pressing Button 0.

The LEDs will flash to indicate the new sample rate. One flash means 44.1, two flashes 48, three 88.2 .. etc.

