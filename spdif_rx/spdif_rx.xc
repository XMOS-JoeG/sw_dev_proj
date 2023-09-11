// Test program for spdif_rx 
#include <xs1.h>
#include <stdio.h>
#include <xclib.h>
#include <platform.h>
#include <xscope.h>
#include <stdint.h>

// Required
on tile[0]: in  buffered    port:32 p_spdif_rx    = XS1_PORT_1O; // mcaudio opt in // 1O is opt, 1N is coax
on tile[0]: clock                   clk_spdif_rx  = XS1_CLKBLK_1;

// Optional if required for board setup.
on tile[0]: out             port    p_ctrl        = XS1_PORT_8D;

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

#pragma unsafe arrays
static inline void spdif_rx_8UI_STD_48(buffered in port:32 p, unsigned &t, unsigned &sample, unsigned &outword)
{
    unsigned crc;
    unsigned ref_tran;
    // lookup table. index can be max of 32 so need 33 element array.
    const unsigned error_lookup[33] = {35,34,33,32,32,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39};
    // 48k standard
    const unsigned unscramble_0x08080404_0xB[16] = {
    0xA0000000, 0x10000000, 0xE0000000, 0x50000000,
    0x20000000, 0x90000000, 0x60000000, 0xD0000000,
    0x70000000, 0xC0000000, 0x30000000, 0x80000000,
    0xF0000000, 0x40000000, 0xB0000000, 0x00000000};

    // Now receive data
    asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
    ref_tran = cls(sample<<9); // Expected value is 2 Possible values are 1 to 32.
    t += error_lookup[ref_tran]; // Lookup next port time based off where current transition was.
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
    sample <<= (ref_tran - 2); // shift the sample to make the transition exactly between bits 20 and 21.
    crc = sample & 0x08080404;
    crc32(crc, 0xF, 0xB);
    outword >>= 4;
    outword |= unscramble_0x08080404_0xB[crc];
}

#pragma unsafe arrays
static inline void spdif_rx_8UI_PRE_48(buffered in port:32 p, unsigned &t, unsigned &sample, unsigned &outword)
{
    unsigned crc;
    unsigned ref_tran;
    // lookup table. index can be max of 32 so need 33 element array.
    const unsigned error_lookup[33] = {35,34,33,32,32,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39,39};
    // 48k preamble
    const unsigned unscramble_0x08080440_0xF[16] = {
    0x10000000, 0x90000000, 0xE0000000, 0x60000000,
    0x50000000, 0xD0000000, 0xA0000000, 0x20000000,
    0x30000000, 0xB0000000, 0xC0000000, 0x40000000,
    0x70000000, 0xF0000000, 0x80000000, 0x00000000};

    // Now receive data
    asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
    ref_tran = cls(sample<<9); // Expected value is 2 Possible values are 1 to 32.
    t += error_lookup[ref_tran]; // Lookup next port time based off where current transition was.
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
    // lookup table. index can be max of 32 so need 33 element array.
    const unsigned error_lookup[33] = {36,36,36,35,35,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42};
    // 44.1k standard
    const unsigned unscramble_0x08080202_0xC[16] = {
    0x70000000, 0xC0000000, 0xA0000000, 0x10000000,
    0x30000000, 0x80000000, 0xE0000000, 0x50000000,
    0x20000000, 0x90000000, 0xF0000000, 0x40000000,
    0x60000000, 0xD0000000, 0xB0000000, 0x00000000};

    // Now receive data
    asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
    ref_tran = cls(sample<<9); // Expected value is 2 Possible values are 1 to 32.
    t += error_lookup[ref_tran]; // Lookup next port time based off where current transition was.
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
    // lookup table. index can be max of 32 so need 33 element array.
    const unsigned error_lookup[33] = {36,36,36,35,35,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42};
    // 44.1k preamble
    const unsigned unscramble_0x08080220_0xC[16] = {
    0x30000000, 0xC0000000, 0xA0000000, 0x50000000,
    0x70000000, 0x80000000, 0xE0000000, 0x10000000,
    0x20000000, 0xD0000000, 0xB0000000, 0x40000000,
    0x60000000, 0x90000000, 0xF0000000, 0x00000000};

    // Now receive data
    asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
    ref_tran = cls(sample<<9); // Expected value is 2 Possible values are 1 to 32.
    t += error_lookup[ref_tran]; // Lookup next port time based off where current transition was.
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
    if (ref_tran > 3)
        ref_tran = 3;
    sample <<= (ref_tran - 2); // shift the sample to make the transition exactly between bits 20 and 21.
    crc = sample & 0x08080220;
    crc32(crc, 0xF, 0xC);
    outword >>= 4;
    outword |= unscramble_0x08080220_0xC[crc];
}

void spdif_rx_48(streaming chanend c, buffered in port:32 p)
{
    unsigned t;
    unsigned pre_check = 0;
    unsigned sample;
    unsigned outword = 0;
    
    // Read the port counter and add a bit.
    p :> void @ t; // read port counter
    t+= 100;
    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));

    // Now receive data
    while(pre_check < 16)
    {
        spdif_rx_8UI_STD_48(p, t, sample, outword);
        pre_check = cls(sample);
        if (pre_check > 10) // Last three bits of old subframe and first "bit" of preamble.
        {
            outword = xor4(outword, (outword << 1), 0xFFFFFFFF, 0x00000000); // This achieves the xor decode plus inverting the output in one step.
            outword <<= 1;
            c <: outword;
            
            // Receive and decode the next input word here because we need to use a different mask to capture the preamble detail.
            spdif_rx_8UI_PRE_48(p, t, sample, outword);
            spdif_rx_8UI_STD_48(p, t, sample, outword);
            spdif_rx_8UI_STD_48(p, t, sample, outword);
            spdif_rx_8UI_STD_48(p, t, sample, outword);
            spdif_rx_8UI_STD_48(p, t, sample, outword);
            spdif_rx_8UI_STD_48(p, t, sample, outword);
            spdif_rx_8UI_STD_48(p, t, sample, outword);
        }
    }
}

void spdif_rx_441(streaming chanend c, buffered in port:32 p)
{
    unsigned t;
    unsigned pre_check = 0;
    unsigned sample;
    unsigned outword = 0;
    
    // Read the port counter and add a bit.
    p :> void @ t; // read port counter
    t+= 100;
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

void spdif_rx(streaming chanend c, buffered in port:32 p, clock clk)
{

    // Configure spdif rx port to be clocked from spdif_rx clock defined below.
    configure_in_port(p, clk);
  
    // Delay a long time to make sure everything is settled
    delay_milliseconds(10);

    int clock_div;
    
    while(1)
    {
        // Pseudocode
        // set spdif_rx running at 44.1kHz
        // get samples from channel, if no sample after a time (min 192 frames @ 44.1 = 4.35ms, call it 5ms). Then timeout and go to next clock div up.
        // if we do get samples, check the preambles alternate in correct fashion {(X or Z), Y} in repeating fashion for say 20 preambles. If ok consider input as good, return this value as current rate.
        // if preambles don't alternate, switch to 48kHz.
        
        // More simple pseudocode
        // Try rx in order 44.1, 48, 88.2, 96, 176.4, 192. For each setting:
        // If timeout or not alternating preamble pattern
        //     go to next speed up
        // else
        //     report sample rate, send samples up to host app.
        
        // Define the clock source for sampling.
        // clock_div = 0 (100/2*0 = 100MHz) for 192/176.4kHz.
        // clock_div = 1 (100/2*1 = 50MHz) for 96/88.2kHz.
        // clock_div = 2 (100/2*2 = 25MHz) for 48/44.1kHz.
        // NB: Technically we could do clock_div = 3 (100/2*3 = 16.66MHz) for 32kHz (part of S/PDIF spec).
        clock_div = 1;
    
        // Stop clock so we can reconfigure it
        stop_clock(clk);
        // Set the desired clock div
        configure_clock_ref(clk, clock_div);
        // Start the clock block running. Port timer will be reset here.
        start_clock(clk);
        
        spdif_rx_441(c, p);
        //spdif_rx_48(c, p);
    }
}

void spdif_receive_sample_jeg(streaming chanend c)
{
    unsigned tmp;
    timer tmr;
    int t;
    unsigned outwords[50000] = {0};
    unsigned times[50000] = {0};
    
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
    unsigned right, left;

    for(int i=0; i<20000; i++)
    {
        if (i > 0)
        {   
            unsigned pre = outwords[i] & 0xF;
            if ((pre == 0x8) | (pre == 0xA)) // Z preamble
                block_count++;
            if ((pre == 0x2) | (pre == 0x0)) // Y preamble (right)
            {
                right = (outwords[i] & ~0xF) << 4;
                left = (outwords[i-1] & ~0xF) << 4;
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
/*             int t_diff = times[i] - times[i-1];
            printf("outword 0x%08X, i %d, t_diff %d\n", outwords[i], i, t_diff); */
        }
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
        on tile[0]: spdif_receive_sample_jeg(c);
        on tile[0]: dummy_thread(0);
        on tile[0]: dummy_thread(1);
        on tile[0]: dummy_thread(2);
        on tile[0]: dummy_thread(3);
        on tile[0]: dummy_thread(4);
        on tile[0]: dummy_thread(5);
    }
    return 0;
}