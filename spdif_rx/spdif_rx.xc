// Test program for spdif_rx
#include <xs1.h>
#include <stdio.h>
#include <xclib.h>
#include <platform.h>
#include <xscope.h>

// Required
on tile[0]: in  buffered    port:32 p_spdif_rx    = XS1_PORT_1O; // mcaudio opt in
on tile[0]: clock                   clk_spdif_rx  = XS1_CLKBLK_1;

// Optional if required for board setup.
on tile[0]: out             port    p_ctrl        = XS1_PORT_8D;

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
    p_ctrl <: 0x20;
    
    // Wait for power supplies to be up and stable.
    delay_milliseconds(10);

    /////////////////////////////
}

void printintBits(int word, int size)
{
    unsigned mask = 1 << (size-1);
    for (int i = 0; i<size; i++)
    {
      if ((word & mask) == mask)
        printf("1");
      else
        printf("0");
      mask >>= 1;
    }
}

static inline int cls(int idata)
{
    int x;
    asm volatile("cls %0, %1" : "=r"(x)  : "r"(idata));
    return x;
}

static inline int sample_and_compress(int inword, int mask)
{
    unsigned crc = inword & mask;
    crc32(crc, ~0, 15);
    crc &= 0xF; // zext
    return crc;
}

#define PORT_PAD_CTL_4mA_SCHMITT   0x00920006

int main(void)
{
    // Setup for MC audio board - turn the power on.
    board_setup();
    
    // Define the clock source for spdif rx sampling.
    // Always use the sw ref clock as source. Use 100MHz (div 0) for 192kHz, 50MHz (div 1) for 96kHz, 25MHz (div 2) for 48kHz.
    configure_clock_ref(clk_spdif_rx, 1);

    // Configure spdif rx port to be clocked from spdif_rx clock defined above.
    configure_in_port(p_spdif_rx, clk_spdif_rx);
    
    start_clock(clk_spdif_rx);

    // Configure the pad if required (used for testing)
    // Uncomment the following line to enable the schmitt trigger on the input pad.
     asm volatile ("setc res[%0], %1" :: "r" (p_spdif_rx), "r" (PORT_PAD_CTL_4mA_SCHMITT));
    // Uncomment the following line to turn on the input pad pulldown.
     asm volatile ("setc res[%0], %1" :: "r" (p_spdif_rx), "r" (0x000B)); // Turn on PULLDOWN
    // Uncomment the following line to turn on the input pad pullup.
    // asm volatile ("setc res[%0], %1" :: "r" (p_spdif_rx), "r" (0x0013)); // Turn on PULLUP
  
    // Delay a long time to make sure everything is settled
    delay_milliseconds(1000);
    
    // REMEMBER ALL WORDS ARE LSB FIRST (TIME GOES BACKWARDS ....)
    
    // Debug only variables ...
    unsigned samples[10000] = {0};
    int err[10000] = {0};
    int pre[10000] = {0};
    unsigned outwords[1500] = {0};
    
    // Real variables
    unsigned t = 100; // Initial port read time.
    unsigned j = 0;
    unsigned outword = 0;
    unsigned unscramble_10101010[16] = {0xF0000000, 0xD0000000, 0x70000000, 0x50000000, 0xE0000000, 0xC0000000, 0x60000000, 0x40000000, 0xB0000000, 0x90000000, 0x30000000, 0x10000000, 0xA0000000, 0x80000000, 0x20000000, 0x00000000};
    unsigned sample;
    int error;
    
    // Start the clock block running. Port timer will be reset here.
    start_clock(clk_spdif_rx);
    
    // Note this will lock to subframe intervals very quickly but will take up to 3072 32 bit sample inputs to lock to Z preambles. So somewhere in that time you may get a large error sample.
    for(int i=0; i<10000;i++)
    {
        p_spdif_rx @ t :> sample;
        error = 18 - cls(sext(sample, 16)); // target is to have a transition between bits 13 and 14 - puts our samples symmetrically in the 32 bit sample.
        sample >>= error; // shift the sample to make the transition exactly between bits 13 and 14.
        outword >>= 4;
        outword |= unscramble_10101010[sample_and_compress(sample, 0x10101010)];
        if (cls(sext(sample, 24)) > 16) // Last two bits of old subframe and first half of preamble.
        {
            outword ^= (outword << 1); // can do in another thread
            outword = outword << 2; // can do in another thread
            outword = ~outword; // can do in another thread
            outwords[j] = outword; // normally output to channel
            j++; // Don't need this for output to channel
            pre[i] = 1; // Mark preamble (debug only)
        }
        // By default we take the next sample at the closest value to how many sampling clock (100/50/25MHz) bits in 8UI.
        // For 48/96/192 this is 32.552 - closest value is 33.
        t += error + 33;
        samples[i] = sample; // debug only
        err[i] = error; // debug only
    } 
   
    for(int i=0; i<200;i++)
    {
        printf("samples[%4d] 0b", i);
        printintBits(samples[i], 32);
        printf(" err %2d, pre %d\n", err[i], pre[i]);
    }
    
    for(int i=0; i<600;i++)
    {
        printf("outwords[%3d] = 0x%08X\n", i, outwords[i]);
    }

    while(1);

    return 0;
}