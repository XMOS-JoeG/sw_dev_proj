// Test program for spdif_rx
#include <xs1.h>
#include <stdio.h>
#include <xclib.h>
#include <platform.h>
#include <xscope.h>
#include <stdint.h>
#include <print.h>

on tile[TILE]: in  buffered    port:32 p_spdif_rx    = XS1_PORT_1O;   // xcore.ai mcaudio 1O is optical, 1N is coax. xc200 1O is optical, 1P is coax
on tile[TILE]: clock                   clk_spdif_rx  = XS1_CLKBLK_1;

// Optional if required for board setup.
on tile[TILE]: out             port    p_ctrl        = XS1_PORT_8D;

// Test port
on tile[TILE]: out             port    p_test        = XS1_PORT_1A;

void exit(int);

void xscope_user_init() {
   xscope_register(0, 0, "", 0, "");
   xscope_config_io(XSCOPE_IO_BASIC);
   xscope_mode_lossless();
}

void board_setup(void)
{
    //////// BOARD SETUP FOR XU316 MC AUDIO ////////

    set_port_drive_high(p_ctrl);

    // Drive control port to turn on 3V3.
    // Bits set to low will be high-z, pulled down.
    p_ctrl <: 0xA0;

    // Wait for power supplies to be up and stable.
    delay_milliseconds(10);

    /////////////////////////////
}

static inline int cls(int idata)
{
    int x;
#if __XS3A__
    asm volatile("cls %0, %1" : "=r"(x)  : "r"(idata));
#else
    x = (clz(idata) + clz(~idata));
#endif
    return x;
}

static inline int xor4(int idata1, int idata2, int idata3, int idata4)
{
    int x;
    asm volatile("xor4 %0, %1, %2, %3, %4" : "=r"(x)  : "r"(idata1), "r"(idata2), "r"(idata3), "r"(idata4));
    return x;
}

// Lookup tables for port time adder based on where the reference transition was.
// Index can be max of 32 so need 33 element array.
// Index 0 is never used.
const unsigned error_lookup_441[33] = {0,36,36,35,35,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42};
const unsigned error_lookup_48[33]  = {0,33,33,32,32,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39};

#pragma unsafe arrays
static inline void spdif_rx_8UI_48(buffered in port:32 p, unsigned &t, unsigned &sample, unsigned &outword, unsigned &unlock_cnt)
{
    unsigned crc;
    unsigned ref_tran;

    // 48k standard
    const unsigned unscramble_0x08080404_0xB[16] = {
    0xA0000000, 0x10000000, 0xE0000000, 0x50000000,
    0x20000000, 0x90000000, 0x60000000, 0xD0000000,
    0x70000000, 0xC0000000, 0x30000000, 0x80000000,
    0xF0000000, 0x40000000, 0xB0000000, 0x00000000};

    // Now receive data
    asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
    ref_tran = cls(sample<<9); // Expected value is 2 Possible values are 1 to 32.
    t += error_lookup_48[ref_tran]; // Lookup next port time based off where current transition was.
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
    if (ref_tran > 4)
      unlock_cnt++;
    else if (ref_tran > 2)
      sample <<= 1;
    crc = sample & 0x08080404;
    crc32(crc, 0xF, 0xB);
    outword >>= 4;
    outword |= unscramble_0x08080404_0xB[crc];
}

#pragma unsafe arrays
static inline void spdif_rx_8UI_441(buffered in port:32 p, unsigned &t, unsigned &sample, unsigned &outword, unsigned &unlock_cnt)
{
    unsigned crc;
    unsigned ref_tran;

    // 44.1k standard
    const unsigned unscramble_0x08080202_0xC[16] = {
    0x70000000, 0xC0000000, 0xA0000000, 0x10000000,
    0x30000000, 0x80000000, 0xE0000000, 0x50000000,
    0x20000000, 0x90000000, 0xF0000000, 0x40000000,
    0x60000000, 0xD0000000, 0xB0000000, 0x00000000};

    // Now receive data
    asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
    ref_tran = cls(sample<<9); // Expected value is 2 Possible values are 1 to 32.
    t += error_lookup_441[ref_tran]; // Lookup next port time based off where current transition was.
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
    if (ref_tran > 4)
      unlock_cnt++;
    else if (ref_tran > 2)
      sample <<= 1;
    crc = sample & 0x08080202;
    crc32(crc, 0xF, 0xC);
    outword >>= 4;
    outword |= unscramble_0x08080202_0xC[crc];
}

void spdif_rx_48(streaming chanend c, buffered in port:32 p)
{
    unsigned sample;
    unsigned outword = 0;
    unsigned z_pre_sample = 0;
    unsigned unlock_cnt = 0;
    unsigned t;
    
    // Read the port counter and add a bit.
    p :> void @ t; // read port counter
    t+= 100;
    // Note, this is inline asm since xc can only express a timed input/output
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));

    // Now receive data
    while(unlock_cnt < 32)
    {
        spdif_rx_8UI_48(p, t, sample, outword, unlock_cnt);
        if (cls(sample) > 9) // Last three bits of old subframe and first "bit" of preamble.
        {
            outword = xor4(outword, (outword << 1), 0xFFFFFFFF, z_pre_sample); // This achieves the xor decode plus inverting the output in one step.
            outword <<= 1;
            c <: outword;

            spdif_rx_8UI_48(p, t, sample, outword, unlock_cnt);
            z_pre_sample = sample;
            spdif_rx_8UI_48(p, t, sample, outword, unlock_cnt);
            spdif_rx_8UI_48(p, t, sample, outword, unlock_cnt);
            spdif_rx_8UI_48(p, t, sample, outword, unlock_cnt);
            if (cls(z_pre_sample<<11) > 9)
              z_pre_sample = 2;
            else
              z_pre_sample = 0;
            spdif_rx_8UI_48(p, t, sample, outword, unlock_cnt);
            spdif_rx_8UI_48(p, t, sample, outword, unlock_cnt);
            spdif_rx_8UI_48(p, t, sample, outword, unlock_cnt);
        }
    }
}

void spdif_rx_441(streaming chanend c, buffered in port:32 p)
{
    unsigned sample;
    unsigned outword = 0;
    unsigned z_pre_sample = 0;
    unsigned unlock_cnt = 0;
    unsigned t;

    // Read the port counter and add a bit.
    p :> void @ t; // read port counter
    t+= 100;
    // Note, this is inline asm since xc can only express a timed input/output
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));

    // Now receive data
    while(unlock_cnt < 32)
    {
        spdif_rx_8UI_441(p, t, sample, outword, unlock_cnt);
        if (cls(sample) > 9) // Last three bits of old subframe and first "bit" of preamble.
        {
            outword = xor4(outword, (outword << 1), 0xFFFFFFFF, z_pre_sample); // This achieves the xor decode plus inverting the output in one step.
            outword <<= 1;
            c <: outword;

            spdif_rx_8UI_441(p, t, sample, outword, unlock_cnt);
            z_pre_sample = sample;
            spdif_rx_8UI_441(p, t, sample, outword, unlock_cnt);
            spdif_rx_8UI_441(p, t, sample, outword, unlock_cnt);
            spdif_rx_8UI_441(p, t, sample, outword, unlock_cnt);
            if (cls(z_pre_sample<<11) > 10)
              z_pre_sample = 2;
            else
              z_pre_sample = 0;
            spdif_rx_8UI_441(p, t, sample, outword, unlock_cnt);
            spdif_rx_8UI_441(p, t, sample, outword, unlock_cnt);
            spdif_rx_8UI_441(p, t, sample, outword, unlock_cnt);
        }
    }
}

// This function checks the port clock is approximately the correct frequency
int check_clock_div(buffered in port:32 p)
{
    unsigned pulse_width;
    unsigned sample;
    for(int i=0; i<100;i++) // Check 100 32bit samples
    {
        p :> sample;
        sample <<= cls(sample); // Shift off the top pulse (likely to not be a complete pulse)
        pulse_width = cls(sample);
        if ((pulse_width < 2) || (pulse_width > 14))
            return 1;
    }
    return 0;
}

void spdif_rx(streaming chanend c, buffered in port:32 p, clock clk, unsigned sample_freq_estimate)
{
    unsigned sample_rate = sample_freq_estimate;

    // Configure spdif rx port to be clocked from spdif_rx clock defined below.
    configure_in_port(p, clk);

    while(1)
    {
        // Determine 100MHz clock divider
        unsigned clock_div = 96001/sample_rate;
          
        // Stop clock so we can reconfigure it
        stop_clock(clk);
        // Set the desired clock div
        configure_clock_ref(clk, clock_div);
        // Start the clock block running. Port timer will be reset here.
        start_clock(clk);
        
        printf("Trying %dHz Rx mode ...\n", sample_rate);

        // Check our clock div value is correct
        if (check_clock_div(p) == 0)
        {
            printf("Entering %dHz decode ...\n", sample_rate);
            if(sample_rate % 44100)
                spdif_rx_48(c, p);
            else
                spdif_rx_441(c, p);
        }

        // Get next sample rate from current sample rate.
        switch(sample_rate)
        {
            case 32000:  sample_rate = 44100;  break;
            case 44100:  sample_rate = 48000;  break;
            case 48000:  sample_rate = 88200;  break;
            case 88200:  sample_rate = 96000;  break;
            case 96000:  sample_rate = 176400; break;
            case 176400: sample_rate = 192000; break;
            case 192000: sample_rate = 32000;  break;
            default:     sample_rate = 48000;  break;
        }
    }
}

// Source sample data for testing only
// One cycle of full scale 24 bit sine wave in 96 samples.
// This will produce 500Hz signal at Fs = 48kHz, 1kHz at 96kHz and 2kHz at 192kHz.
const int32_t sine_table1[96] =
{
    0x000000,0x085F21,0x10B515,0x18F8B8,0x2120FB,0x2924ED,0x30FBC5,0x389CEA,
    0x3FFFFF,0x471CEC,0x4DEBE4,0x546571,0x5A8279,0x603C49,0x658C99,0x6A6D98,
    0x6ED9EB,0x72CCB9,0x7641AE,0x793501,0x7BA374,0x7D8A5E,0x7EE7A9,0x7FB9D6,
    0x7FFFFF,0x7FB9D6,0x7EE7A9,0x7D8A5E,0x7BA374,0x793501,0x7641AE,0x72CCB9,
    0x6ED9EB,0x6A6D98,0x658C99,0x603C49,0x5A8279,0x546571,0x4DEBE4,0x471CEC,
    0x3FFFFF,0x389CEA,0x30FBC5,0x2924ED,0x2120FB,0x18F8B8,0x10B515,0x085F21,
    0x000000,0xF7A0DF,0xEF4AEB,0xE70748,0xDEDF05,0xD6DB13,0xCF043B,0xC76316,
    0xC00001,0xB8E314,0xB2141C,0xAB9A8F,0xA57D87,0x9FC3B7,0x9A7367,0x959268,
    0x912615,0x8D3347,0x89BE52,0x86CAFF,0x845C8C,0x8275A2,0x811857,0x80462A,
    0x800001,0x80462A,0x811857,0x8275A2,0x845C8C,0x86CAFF,0x89BE52,0x8D3347,
    0x912615,0x959268,0x9A7367,0x9FC3B7,0xA57D87,0xAB9A8F,0xB2141C,0xB8E314,
    0xC00001,0xC76316,0xCF043B,0xD6DB13,0xDEDF05,0xE70748,0xEF4AEB,0xF7A0DF
};

// Two cycles of full scale 24 bit sine wave in 96 samples.
// This will produce 1kHz signal at Fs = 48kHz, 2kHz at 96kHz and 4kHz at 192kHz.
const int32_t sine_table2[96] =
{
    0x000000,0x10B515,0x2120FB,0x30FBC5,0x3FFFFF,0x4DEBE4,0x5A8279,0x658C99,
    0x6ED9EB,0x7641AE,0x7BA374,0x7EE7A9,0x7FFFFF,0x7EE7A9,0x7BA374,0x7641AE,
    0x6ED9EB,0x658C99,0x5A8279,0x4DEBE4,0x3FFFFF,0x30FBC5,0x2120FB,0x10B515,
    0x000000,0xEF4AEB,0xDEDF05,0xCF043B,0xC00001,0xB2141C,0xA57D87,0x9A7367,
    0x912615,0x89BE52,0x845C8C,0x811857,0x800001,0x811857,0x845C8C,0x89BE52,
    0x912615,0x9A7367,0xA57D87,0xB2141C,0xC00001,0xCF043B,0xDEDF05,0xEF4AEB,
    0x000000,0x10B515,0x2120FB,0x30FBC5,0x3FFFFF,0x4DEBE4,0x5A8279,0x658C99,
    0x6ED9EB,0x7641AE,0x7BA374,0x7EE7A9,0x7FFFFF,0x7EE7A9,0x7BA374,0x7641AE,
    0x6ED9EB,0x658C99,0x5A8279,0x4DEBE4,0x3FFFFF,0x30FBC5,0x2120FB,0x10B515,
    0x000000,0xEF4AEB,0xDEDF05,0xCF043B,0xC00001,0xB2141C,0xA57D87,0x9A7367,
    0x912615,0x89BE52,0x845C8C,0x811857,0x800001,0x811857,0x845C8C,0x89BE52,
    0x912615,0x9A7367,0xA57D87,0xB2141C,0xC00001,0xCF043B,0xDEDF05,0xEF4AEB
};


#pragma unsafe arrays
void spdif_receive_sample(streaming chanend c)
{
    unsigned tmp;
    timer tmr;
    int t;
    unsigned outwords[20000] = {0};
    unsigned times[20000] = {0};

/*     while(1)
    {
        c :> tmp;
        p_test <: 0;
        c :> tmp;
        p_test <: 1;
    } */

    for(int i = 0; i<20000;i++)
    {
        c :> tmp;
        tmr :> t;
        times[i] = t;
        outwords[i] = tmp;
    }
    
/*     int t_diff;
    for(int i = 0; i<200;i++)
    {
        if (i == 0)
            t_diff = times[i] - 0;
        else
            t_diff = times[i] - times[i-1];
        printf("outwords[%d] = 0x%08X, t_diff = %d\n", i, outwords[i], t_diff);
    } */

    // Manually parse the output words to look for errors etc.
    // Based on known TX samples from spdif tx program.
    unsigned errors = 0;
    unsigned ok = 0;
    unsigned block_count = 0;
    int i_last =0;
    for(int i=0; i<20000; i++)
    {
        unsigned pre = outwords[i] & 0xC;
        //int t_diff = times[i] - times[i-1];

        if (pre == 0x8) // Z preamble
        {
            block_count++;
            printf("Block Start!, sample_count = %d\n", (i-i_last));
            i_last = i;
            unsigned expected = 0;
            for(int j=0; j<192;j++)
            {
                unsigned index = j/2;
                if (j==0)
                {
                    expected = (sine_table1[index % 96] << 4) | 0x8;
                }
                else if (j%2 == 0)
                {
                    expected = (sine_table1[index % 96] << 4) | 0xC;
                }
                else if (j%2 == 1)
                {
                    expected = (sine_table2[index % 96] << 4) | 0x0;
                }

                if (i+j == 20000)
                    break;
                unsigned checkword = outwords[i+j] & 0x0FFFFFFC;
                if (checkword != expected)
                {
                    errors++;
                    printf("Error checkword 0x%08X, expected 0x%08X, i %d, j %d\n", checkword, expected, i, j);
                }
                else
                {
                    ok++;
                    //printf("OK    checkword 0x%08X, expected 0x%08X, i %d, j %d\n", checkword, expected, i, j);
                }

            }
            i+=192;
        }
    }
    printf("Error count %d, ok count %d, block_count %d\n", errors, ok, block_count);

    while(1);

}

void dummy_thread(int thread)
{
    unsigned i=0;

    while(1)
    {
        i+=4;
        if (i == 0)
        {
            printf("thread %d\n", thread);
        }
    }
}

int main(void) {
    streaming chan c;
    par
    {
        on tile[TILE]:
        {
            #ifndef XC200
            board_setup();
            #endif
            spdif_rx(c, p_spdif_rx, clk_spdif_rx, 32000);
        }
        on tile[TILE]: spdif_receive_sample(c);
        on tile[TILE]: dummy_thread(0);
        on tile[TILE]: dummy_thread(1);
        on tile[TILE]: dummy_thread(2);
        on tile[TILE]: dummy_thread(3);
        on tile[TILE]: dummy_thread(4);
        on tile[TILE]: dummy_thread(5);
    }
    return 0;
}
