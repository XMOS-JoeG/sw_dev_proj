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
    asm volatile("cls %0, %1" : "=r"(x)  : "r"(idata)); // xs3 on.
    #else
    x = (clz(idata) + clz(~idata)); // For xs2.
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
static inline void spdif_rx_8UI_48(buffered in port:32 p, unsigned &t, unsigned &sample, unsigned &outword)
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
    if (ref_tran > 2)
      sample <<= 1;
    crc = sample & 0x08080404;
    crc32(crc, 0xF, 0xB);
    outword >>= 4;
    outword |= unscramble_0x08080404_0xB[crc];
}

#pragma unsafe arrays
static inline void spdif_rx_8UI_441(buffered in port:32 p, unsigned &t, unsigned &sample, unsigned &outword)
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
    if (ref_tran > 2)
      sample <<= 1;
    crc = sample & 0x08080202;
    crc32(crc, 0xF, 0xC);
    outword >>= 4;
    outword |= unscramble_0x08080202_0xC[crc];
}

void spdif_rx_48(streaming chanend c, buffered in port:32 p, unsigned &t)
{
    unsigned pre_check = 0;
    unsigned sample;
    unsigned outword = 0;
    unsigned z_pre_sample = 0;
    
    // Set the initial port time
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));

    // Now receive data
    while(pre_check < 16)
    {
        spdif_rx_8UI_48(p, t, sample, outword);
        pre_check = cls(sample);
        if (pre_check > 9) // Last three bits of old subframe and first "bit" of preamble.
        {
            outword = xor4(outword, (outword << 1), 0xFFFFFFFF, z_pre_sample); // This achieves the xor decode plus inverting the output in one step.
            outword <<= 1;
            c <: outword;

            spdif_rx_8UI_48(p, t, sample, outword);
            z_pre_sample = sample;
            spdif_rx_8UI_48(p, t, sample, outword);
            spdif_rx_8UI_48(p, t, sample, outword);
            spdif_rx_8UI_48(p, t, sample, outword);
            if (cls(z_pre_sample<<11) > 9)
              z_pre_sample = 2;
            else
              z_pre_sample = 0;
            spdif_rx_8UI_48(p, t, sample, outword);
            spdif_rx_8UI_48(p, t, sample, outword);
            spdif_rx_8UI_48(p, t, sample, outword);
        }
    }
}

void spdif_rx_441(streaming chanend c, buffered in port:32 p, unsigned &t)
{
    unsigned pre_check = 0;
    unsigned sample;
    unsigned outword = 0;
    unsigned z_pre_sample = 0;
    
    // Set the initial port time
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));

    // Now receive data
    while(pre_check < 16)
    {
        spdif_rx_8UI_441(p, t, sample, outword);
        pre_check = cls(sample);
        if (pre_check > 9) // Last three bits of old subframe and first "bit" of preamble.
        {
            outword = xor4(outword, (outword << 1), 0xFFFFFFFF, z_pre_sample); // This achieves the xor decode plus inverting the output in one step.
            outword <<= 1;
            c <: outword;
            
            spdif_rx_8UI_441(p, t, sample, outword);
            z_pre_sample = sample;
            spdif_rx_8UI_441(p, t, sample, outword);
            spdif_rx_8UI_441(p, t, sample, outword);
            spdif_rx_8UI_441(p, t, sample, outword);
            if (cls(z_pre_sample<<11) > 10)
              z_pre_sample = 2;
            else
              z_pre_sample = 0;
            spdif_rx_8UI_441(p, t, sample, outword);
            spdif_rx_8UI_441(p, t, sample, outword);
            spdif_rx_8UI_441(p, t, sample, outword);
        }
    }
}

// This initial sync locks the DLL onto stream (inc. Z preamble) and checks if it is OK for decode.
#pragma unsafe arrays
int initial_sync_441(buffered in port:32 p, unsigned &t, unsigned clock_div)
{
    // Initial lock to start of preambles and check our sampling freq is correct.
    // We will very quickly lock into one of two positions in the stream (where data transitions every 8UI)
    // This can happen in two places when you consider X and Y preambles and these are very frequent.
    // There is only one position we can lock when considering all three (X, Y and Z) preambles.
    unsigned ref_tran;
    unsigned sample;
    int t_block = 0;
    timer tmr;
    unsigned tmp;
    
    // Read the port counter and add a bit.
    p :> void @ t; // read port counter
    t+= 100;
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
    
    for(int i=0; i<20000;i++)
    {
        asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
        ref_tran = cls(sample<<9); // Expected value is 2 Possible values are 1 to 32.
        t += error_lookup_441[ref_tran]; // Lookup next port time based off where current transition was.
        asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
        if (ref_tran > 16)
            break;
        if (ref_tran > 2)
            sample <<= 1;
        if (cls(sample) > 9)
        {
            asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
            ref_tran = cls(sample<<10);
            t += error_lookup_441[ref_tran]; // Lookup next port time based off where current transition was.
            asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
            if (ref_tran > 2)
                sample <<= 1;
            //look for a z preamble
            if (cls(sample<<11) > 10) // Z preamble
            {
                tmr :> tmp;
                if (t_block == 0)
                {
                    t_block = tmp;
                }
                else
                {
                    t_block = tmp - t_block;
                    asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p)); // empty the transfer reg
                    break;
                }
            }
        }
    }
    
    int t_block_targ;
    int t_block_err;
    // samplefreq  clockdiv  target (192/sr)
    // 44100       2         4.354ms
    // 88200       1         2.177ms
    // 176400      0         1.088ms
    t_block_targ = 108843 << clock_div;
    t_block_err = t_block - t_block_targ;
    
    t+=70; // Add an 8UI*2 time adder to ensure we have enough instruction time before next IN.
    //printf("t_block = %d\n", t_block);
    if ((t_block_err > -435) && (t_block_err < 435))
        return 0;
    else
        return 1;
}

// This initial sync locks the DLL onto stream (inc. Z preamble) and checks if it is OK for decode.
#pragma unsafe arrays
int initial_sync_48(buffered in port:32 p, unsigned &t, unsigned clock_div)
{
    // Initial lock to start of preambles and check our sampling freq is correct.
    // We will very quickly lock into one of two positions in the stream (where data transitions every 8UI)
    // This can happen in two places when you consider X and Y preambles and these are very frequent.
    // There is only one position we can lock when considering all three (X, Y and Z) preambles.
    unsigned ref_tran;
    unsigned sample;
    int t_block = 0;
    timer tmr;
    unsigned tmp;
    
    // Read the port counter and add a bit.
    p :> void @ t; // read port counter
    t+= 100;
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
    
    for(int i=0; i<20000;i++)
    {
        asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
        ref_tran = cls(sample<<9); // Expected value is 2 Possible values are 1 to 32.
        t += error_lookup_48[ref_tran]; // Lookup next port time based off where current transition was.
        asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
        if (ref_tran > 16)
            break;
        if (ref_tran > 2)
            sample <<= 1;
        if (cls(sample) > 9)
        {
            asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
            ref_tran = cls(sample<<9);
            t += error_lookup_48[ref_tran]; // Lookup next port time based off where current transition was.
            asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
            if (ref_tran > 2)
                sample <<= 1;
            //look for a z preamble
            if (cls(sample<<11) > 9) // Z preamble
            {
                tmr :> tmp;
                if (t_block == 0)
                {
                    t_block = tmp;
                }
                else
                {
                    t_block = tmp - t_block;
                    asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p)); // empty the transfer reg
                    break;
                }
            }
        }
    }
    
    int t_block_targ;
    int t_block_err;
    // samplefreq  clockdiv  target (192/sr)
    // 48000       2         4ms
    // 96000       1         2ms
    // 192000      0         1ms
    t_block_targ = 100000 << clock_div;
    t_block_err = t_block - t_block_targ;
    
    t+=65; // Add an 8UI time adder to ensure we have enough instruction time before next IN.
    //printf("t_block = %d\n", t_block);
    if ((t_block_err > -400) && (t_block_err < 400))
        return 0;
    else
        return 1;
}

void spdif_rx(streaming chanend c, buffered in port:32 p, clock clk)
{
    // Configure spdif rx port to be clocked from spdif_rx clock defined below.
    configure_in_port(p, clk);
    
    while(1)
    {
        for(int clock_div = 0; clock_div < 3; clock_div++) // Loop over different sampling freqs (100/50/25MHz)
        {
            //printf("clock_div = %d\n", clock_div);
        
            // Stop clock so we can reconfigure it
            stop_clock(clk);
            // Set the desired clock div
            configure_clock_ref(clk, clock_div);
            // Start the clock block running. Port timer will be reset here.
            start_clock(clk);
            
            // We now test to see if the 44.1 base rate decode will work, if not we switch to 48.
            unsigned t;
            if (initial_sync_441(p, t, clock_div) == 0)
            {
                spdif_rx_441(c, p, t);  // We pass in start time so that we start in sync.
                printf("Exit %dHz Mode\n", (176400>>clock_div));
            }
            else if (initial_sync_48(p, t, clock_div) == 0)
            {
                spdif_rx_48(c, p, t);
                printf("Exit %dHz Mode\n", (192000>>clock_div));
            }
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
    
    // Manually parse the output words to look for errors etc.
    // Based on known TX samples from spdif tx program.
    unsigned errors = 0;
    unsigned ok = 0;
    unsigned block_count = 0;
    for(int i=0; i<20000; i++)
    {
        unsigned pre = outwords[i] & 0xC;
        //int t_diff = times[i] - times[i-1];
        
        if (pre == 0x8) // Z preamble
        {
            block_count++;
            printf("Block Start!, i = %d\n", i);
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
            spdif_rx(c, p_spdif_rx, clk_spdif_rx);
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