// Test program for spdif_rx 
#include <xs1.h>
#include <stdio.h>
#include <xclib.h>
#include <platform.h>
#include <xscope.h>
#include <stdint.h>
#include <print.h>

// Required
on tile[0]: in  buffered    port:32 p_spdif_rx    = XS1_PORT_1N; // mcaudio opt in // 1O is opt, 1N is coax
on tile[0]: clock                   clk_spdif_rx  = XS1_CLKBLK_1;

// Optional if required for board setup.
on tile[0]: out             port    p_ctrl        = XS1_PORT_8D;

// Test port
on tile[0]: out             port    p_test        = XS1_PORT_1A;

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
    asm volatile("cls %0, %1" : "=r"(x)  : "r"(idata)); // xs3 on.
    //x = (clz(idata) + clz(~idata)); // For xs2.
    return x;
}

static inline int xor4(int idata1, int idata2, int idata3, int idata4)
{
    int x;
    asm volatile("xor4 %0, %1, %2, %3, %4" : "=r"(x)  : "r"(idata1), "r"(idata2), "r"(idata3), "r"(idata4));
    return x;
}

// Lookup tables for port times. index can be max of 32 so need 33 element array.
const unsigned error_lookup_441[33] = {36,36,36,35,35,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42};
const unsigned error_lookup_48[33]  = {35,34,33,32,32,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39};

#pragma unsafe arrays
static inline void spdif_rx_8UI_STD_48(buffered in port:32 p, unsigned &t, unsigned &sample, unsigned &ref_tran, unsigned &outword)
{
    unsigned crc;

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
    sample <<= (ref_tran - 2); // shift the sample to make the transition exactly between bits 20 and 21.
    crc = sample & 0x08080404;
    crc32(crc, 0xF, 0xB);
    outword >>= 4;
    outword |= unscramble_0x08080404_0xB[crc];
}

#pragma unsafe arrays
static inline void spdif_rx_8UI_PRE_48(buffered in port:32 p, unsigned &t, unsigned &sample, unsigned &ref_tran, unsigned &outword)
{
    unsigned crc;

    // 48k preamble
    const unsigned unscramble_0x08080440_0xF[16] = {
    0x10000000, 0x90000000, 0xE0000000, 0x60000000,
    0x50000000, 0xD0000000, 0xA0000000, 0x20000000,
    0x30000000, 0xB0000000, 0xC0000000, 0x40000000,
    0x70000000, 0xF0000000, 0x80000000, 0x00000000};

    // Now receive data
    asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
    ref_tran = cls(sample<<9); // Expected value is 2 Possible values are 1 to 32.
    t += error_lookup_48[ref_tran]; // Lookup next port time based off where current transition was.
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
    sample <<= (ref_tran - 2); // shift the sample to make the transition exactly between bits 20 and 21.
    crc = sample & 0x08080440;
    crc32(crc, 0xF, 0xF);
    outword >>= 4;
    outword |= unscramble_0x08080440_0xF[crc];
}

#pragma unsafe arrays
static inline void spdif_rx_8UI_STD_441(buffered in port:32 p, unsigned &t, unsigned &sample, unsigned &outword)
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
    if (ref_tran > 3)
        ref_tran = 3;
    sample <<= (ref_tran - 2); // shift the sample to make the transition exactly between bits 20 and 21.
    crc = sample & 0x08080202;
    crc32(crc, 0xF, 0xC);
    outword >>= 4;
    outword |= unscramble_0x08080202_0xC[crc];
}

#pragma unsafe arrays
static inline void spdif_rx_8UI_PRE_441(buffered in port:32 p, unsigned &t, unsigned &sample, unsigned &outword)
{
    unsigned crc;
    unsigned ref_tran;

    // 44.1k preamble
    const unsigned unscramble_0x08080220_0xC[16] = {
    0x30000000, 0xC0000000, 0xA0000000, 0x50000000,
    0x70000000, 0x80000000, 0xE0000000, 0x10000000,
    0x20000000, 0xD0000000, 0xB0000000, 0x40000000,
    0x60000000, 0x90000000, 0xF0000000, 0x00000000};

    // Now receive data
    asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
    ref_tran = cls(sample<<9); // Expected value is 2 Possible values are 1 to 32.
    t += error_lookup_441[ref_tran]; // Lookup next port time based off where current transition was.
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
    if (ref_tran > 3)
        ref_tran = 3;
    sample <<= (ref_tran - 2); // shift the sample to make the transition exactly between bits 20 and 21.
    crc = sample & 0x08080220;
    crc32(crc, 0xF, 0xC);
    outword >>= 4;
    outword |= unscramble_0x08080220_0xC[crc];
}

void spdif_rx_48(streaming chanend c, buffered in port:32 p, unsigned &t)
{
    unsigned pre_check = 0;
    unsigned sample;
    unsigned outword = 0;
    unsigned ref_tran = 0;
    
    // Set the initial port time
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));

    // Now receive data
    while(ref_tran < 16)
    {
        spdif_rx_8UI_STD_48(p, t, sample, ref_tran, outword);
        pre_check = cls(sample);
        if (pre_check > 10) // Last three bits of old subframe and first "bit" of preamble.
        {
            outword = xor4(outword, (outword << 1), 0xFFFFFFFF, 0x00000000); // This achieves the xor decode plus inverting the output in one step.
            outword <<= 1;
            c <: outword;
            
            // Receive and decode the next input word here because we need to use a different mask to capture the preamble detail.
            spdif_rx_8UI_PRE_48(p, t, sample, ref_tran, outword);
            spdif_rx_8UI_STD_48(p, t, sample, ref_tran, outword);
            spdif_rx_8UI_STD_48(p, t, sample, ref_tran, outword);
            spdif_rx_8UI_STD_48(p, t, sample, ref_tran, outword);
            spdif_rx_8UI_STD_48(p, t, sample, ref_tran, outword);
            spdif_rx_8UI_STD_48(p, t, sample, ref_tran, outword);
            spdif_rx_8UI_STD_48(p, t, sample, ref_tran, outword);
        }
    }
}

void spdif_rx_441(streaming chanend c, buffered in port:32 p, unsigned &t)
{
    unsigned pre_check = 0;
    unsigned sample;
    unsigned outword = 0;
    
    // Set the initial port time
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));

    // Now receive data
    while(pre_check < 16)
    {
        spdif_rx_8UI_STD_441(p, t, sample, outword);
        pre_check = cls(sample);
        if (pre_check > 10) // Last three bits of old subframe and first "bit" of preamble.
        {
            outword = xor4(outword, (outword << 1), 0xFFFFFFFF, 0x00000000); // This achieves the xor decode plus inverting the output in one step.
            outword <<= 1;
            c <: outword;
            
            // Receive and decode the next input word here because we need to use a different mask to capture the preamble detail.
            spdif_rx_8UI_PRE_441(p, t, sample, outword);
            spdif_rx_8UI_STD_441(p, t, sample, outword);
            spdif_rx_8UI_STD_441(p, t, sample, outword);
            spdif_rx_8UI_STD_441(p, t, sample, outword);
            spdif_rx_8UI_STD_441(p, t, sample, outword);
            spdif_rx_8UI_STD_441(p, t, sample, outword);
            spdif_rx_8UI_STD_441(p, t, sample, outword);
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
        ref_tran = cls(sample<<10); // Expected value is 2 Possible values are 1 to 32.
        t += error_lookup_441[ref_tran]; // Lookup next port time based off where current transition was.
        asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
        if (ref_tran > 16)
            break;
        sample <<= (ref_tran - 2); // shift the sample to make the transition exactly between bits 19 and 20.
        if (cls(sample) > 11)
        {
            asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
            ref_tran = cls(sample<<10);
            t += error_lookup_441[ref_tran]; // Lookup next port time based off where current transition was.
            asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
            sample <<= (ref_tran - 2); // shift the sample to make the transition exactly between bits 19 and 20.
            //look for a z preamble
            if (cls(sample<<12) > 11) // Z preamble
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
        sample <<= (ref_tran - 2); // shift the sample to make the transition exactly between bits 20 and 21.
        if (cls(sample) > 10)
        {
            asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
            ref_tran = cls(sample<<9);
            t += error_lookup_48[ref_tran]; // Lookup next port time based off where current transition was.
            asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
            sample <<= (ref_tran - 2); // shift the sample to make the transition exactly between bits 20 and 21.
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

#pragma unsafe arrays
void spdif_receive_sample(streaming chanend c)
{
    unsigned tmp;
    timer tmr;
    int t;
    unsigned outwords[50000] = {0};
    unsigned times[50000] = {0};
    
    while(1)
    {
        c :> tmp;
        p_test <: 0;
        c :> tmp;
        p_test <: 1;
    }
    
    for(int i = 0; i<50000;i++)
    {
        c :> tmp;
        tmr :> t;
        times[i] = t;
        outwords[i] = tmp;
    }
    
    // Manually parse the output words to look for errors etc.
    unsigned errors = 0;
    unsigned ok = 0;
    unsigned block_count = 0;
    unsigned right = 0;
    unsigned left = 0;

    for(int i=0; i<400; i++)
    {
        unsigned pre = outwords[i] & 0xC;
        unsigned sample = (outwords[i] & ~0xF) << 4;
        
        if (pre == 0x8) // Z preamble
        {
            block_count++;
            printf("Block Start!\n");
            left = sample;
        }
        else if (pre == 0xC) // X preamble
        {
            left = sample;
        }
        if (pre == 0x0) // Y preamble (right)
        {
            right = sample;

            int t_diff = times[i] - times[i-1];
            if (right != left)
            {
                errors++;
                printf("Error left 0x%08X, right 0x%08X, i %d, time %d\n", left, right, i, t_diff);
                //printf("Error left 0x%08X, right 0x%08X, i %d, time %d\n", outwords[i-1], outwords[i], i, t_diff);
            }
            else
            {
                ok++;
                //printf("OK    left 0x%08X, right 0x%08X, i %d, time %d\n", left, right, i, t_diff);
                //printf("OK    left 0x%08X, right 0x%08X, i %d, time %d\n", outwords[i-1], outwords[i], i, t_diff);
            }
        }
        int t_diff = 0;
        if (i>0)
            t_diff = times[i] - times[i-1];
        printf("outword 0x%08X, i %d, t_diff %d\n", outwords[i], i, t_diff);
    }
    
    printf("Error count %d, ok count %d, block_count %d\n", errors, ok, block_count);

    exit(1);
  
}

void dummy_thread(int thread)
{
    unsigned i=0;
    set_core_fast_mode_on();
    
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
        on tile[0]: {
            board_setup();
            spdif_rx(c, p_spdif_rx, clk_spdif_rx);
        }
        on tile[0]: spdif_receive_sample(c);
        on tile[0]: dummy_thread(0);
        on tile[0]: dummy_thread(1);
        on tile[0]: dummy_thread(2);
        on tile[0]: dummy_thread(3);
        on tile[0]: dummy_thread(4);
        on tile[0]: dummy_thread(5);
    }
    return 0;
}