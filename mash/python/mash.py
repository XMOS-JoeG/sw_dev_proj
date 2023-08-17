import math
import numpy
import csv

# Total number of samples in the input and output data sets
#sample_count = 1048576
sample_count = 1024

# delta sigma modulator accumulator width in bits
ACCUM_WIDTH = 20

# Define the input samples to the modulator over time.

# To be clear about the modulation:
# All 0 bits at input (min) produce an output of 0 (on average)
# All 1 bits at input (max) produce an output of 1 - (1/2^ACCUM_WIDTH)
# So each input bit corresponds to an output of (1/(2^ACCUM_WIDTH))
# np.clip(n, minN, maxN)

# Static input as a float
desired_mod_input = 0.51


print("Desired Modulator input: " + str(desired_mod_input))
# Map 0.0 to 1.0 input to 0 to (2^ACCUM_WIDTH)-1 max input. clip at (2^ACCUM_WIDTH)-1.
dc_input_static = round(numpy.clip(((2**ACCUM_WIDTH) * desired_mod_input), 0, ((2**ACCUM_WIDTH)-1)))
actual_mod_input = dc_input_static/(2**ACCUM_WIDTH)
print("Quantised Actual Modulator input is " + str(dc_input_static) + "/" + str(2**ACCUM_WIDTH) + " = Hex " + hex(dc_input_static) + "/" + str(hex(2**ACCUM_WIDTH)) + " = " +str(actual_mod_input))

# Example 3 bit input
# Mod input
# binary bits = decimal = modulator output
# 000 = dec 0 = 0/8 = 0.000
# 001 = dec 1 = 1/8 = 0.125
# 010 = dec 2 = 2/8 = 0.250
# 011 = dec 3 = 3/8 = 0.375
# 100 = dec 4 = 4/8 = 0.500
# 101 = dec 5 = 5/8 = 0.675
# 110 = dec 6 = 6/8 = 0.750
# 111 = dec 7 = 7/8 = 0.875 (max output)

# So each bit corresponds to an output value of 1/8.

dc_input = []
for i in range(sample_count):
  dc_input.append(dc_input_static)
  

# Now define the modulator itself

# m bit accumulator with sum and carry out
# inputs a and b are m bits wide.
def accum_carry(a, b, m):
    # Mask off any input data above m bits
    mask = ((1 << m) - 1) # Mask is all 1s, m bits wide.
    a = a & mask # Just keep bottom m bits.
    b = b & mask # Just keep bottom m bits.
    sum = a + b
    carry = (sum & (1 << m)) >> m # Pull out the carry bit at bit position (m + 1)
    sum = sum & mask # Mask off carry bit, just keep bottom m bits.
    return sum, carry

# The three stage MASH 1-1-1 modulator
def MASH_1_1_1(data_in):
  "This outputs an 8-level (-3 to +4 inclusive) 1-1-1 MASH modulated data set from an input data set of floating point samples"
  data_out = []
  # reset/initial values of flops
  q0 = 1 # Set this to a small odd number. If we set 0 and then only provide a fixed input we are likely to get repeating patterns. Not terribly important, we can always seed random values in here by setting the modulator input to a random number for a while and then setting the value we want.
  q1 = 0
  q2 = 0
  c1_d = 0
  c2_d = 0
  c2_d_d = 0
  for i in range(len(data_in)):
    d0, c0 = accum_carry(q0, data_in[i], ACCUM_WIDTH)
    d1, c1 = accum_carry(q1, d0        , ACCUM_WIDTH)
    d2, c2 = accum_carry(q2, d1        , ACCUM_WIDTH)
    # build output
    first  = c0
    second = first + (c1 - c1_d)
    third  =  second + c2 - (c2_d << 1) + c2_d_d
    data_out.append(third)
    # Time has ticked so update all our variables
    # Latches
    q0 = d0
    q1 = d1
    q2 = d2
    # Delayed Carry flip flops
    c2_d_d = c2_d
    c2_d = c2
    c1_d = c1
  return data_out

# Produce a modulated output from the input.
delta_sigma_out = MASH_1_1_1(dc_input)

print("Average of output is " + str(sum(delta_sigma_out) / len(delta_sigma_out)))

#Print the output
# print("SampleNo,SampleValue")
# for i in range(sample_count):
  # print(str(i) + "," + str(delta_sigma_out[i]))

filename = "output_" + str(ACCUM_WIDTH) + "bit_" + hex(dc_input_static) + ".csv"
with open(filename, 'w', encoding='UTF8') as f:
    writer = csv.writer(f)
    writer.writerow(delta_sigma_out)

# Now lets FFT the output stream
fft_input = delta_sigma_out

# Define a window for the input data
kaiser_beta = 20
window = numpy.kaiser(len(delta_sigma_out), kaiser_beta)

# Apply the window to the input data
# We also subtract the modulator input from the output data to avoid seeing this DC offset in the low freq of the FFT output.
windowed_data = []
for i in range(len(fft_input)):
  windowed_data.append(window[i] * (fft_input[i] - actual_mod_input))

# Perform the FFT to get the complex spectrum
complex_spectrum = numpy.fft.fft(windowed_data)

# So let's get rid of output samples from M/2 to M-1
complex_spectrum = complex_spectrum[:int(sample_count/2)]

# Now convert complex (rectangular) output into polar form (magnitude and phase). We throw away phase and are only interested in magnitude
magnitude_spectrum = []
for item in complex_spectrum:
  magnitude_spectrum.append(abs(item))

# Now lets plot a dB spectrum

# Define 0dB as the maximum magnitude signal we would expect on the input (a full sin wave of -3 to +4 (range of 8)) this is equal to the FFT size which is the sample_count
mag_array_max = sample_count

# The highest bin is at fft_length(sample_count)/2 which is the input toggling every bit.
# in out real system this would correspond with a phase noise spike at PFC freq/2.
# We don't know the PFC freq so add as an input.

# Define the frequency of the PFC input in our PLL system. This is the ref freq (typically 24MHz) divided by the input divider.
pfc_freq = 6000000 #6MHz
bin_width = pfc_freq/sample_count

# Create a new array showing the magnitude in dB
db_spectrum = []
for item in magnitude_spectrum:
  if (item == 0): # Cannot do a log of 0
    value = 0.000000000000000001
  else:
    value = item
  db_spectrum.append(20*math.log10(abs(value/mag_array_max)))

xaxis = []
for i in range(int(sample_count/2)):
  xaxis.append(i*bin_width)

import matplotlib.pyplot as plt

plt.plot(delta_sigma_out, drawstyle='steps-post')
plt.plot(delta_sigma_out, 'o', color='grey', alpha=0.3)
plt.title('Output Samples')
plt.ylabel('Sample Value')
plt.ylim(-3, 4)
plt.xlabel('Sample Number')
plt.xlim(0,(sample_count-1))
plt.savefig("samples.png")
plt.show()

plt.plot(xaxis, db_spectrum)
plt.title('Signal Spectrum')
plt.ylabel('Magnitude (dB)')
plt.ylim(-180, 0)
plt.xlabel('Phase Noise Frequency (Hz)')
plt.xscale('log')
plt.grid(True, linestyle='-.')
plt.tick_params(labelcolor='r', labelsize='medium', width=3)
plt.savefig("spectrum.png")
plt.show()