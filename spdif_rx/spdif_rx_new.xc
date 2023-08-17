// Test program for spdif_rx
#include <xs1.h>
#include <stdio.h>
#include <xclib.h>
#include <platform.h>
#include <xscope.h>
#include <spdif.h>
#include <xassert.h>

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

void spdif_rx(streaming chanend c, buffered in port:32 p, clock clk)
{

    // Configure spdif rx port to be clocked from spdif_rx clock defined below.
    configure_in_port(p, clk);
    
    // REMEMBER ALL WORDS ARE LSB FIRST (TIME GOES BACKWARDS ....)
    
    // Real variables
    int t;
    unsigned outword = 0;
    unsigned unscramble_10101010[16] = {0xF, 0xD, 0x7, 0x5, 0xE, 0xC, 0x6, 0x4, 0xB, 0x9, 0x3, 0x1, 0xA, 0x8, 0x2, 0x0};
    unsigned unscramble_40201008[16] = {0x4, 0x6, 0x5, 0x7, 0xB, 0x9, 0xA, 0x8, 0xC, 0xE, 0xD, 0xF, 0x3, 0x1, 0x2, 0x0};
    unsigned sample;
    int error;
    unsigned unscramble[16];
    unsigned t_add;
    unsigned sample_mask;
    unsigned pre_det_point;
    unsigned z_pre_det_point;
    int clock_div;
    unsigned raw_cls;
    unsigned max_pulse;

    while(1)
    {
        // Stop clock so we can reconfigure it
        stop_clock(clk);
        // Set the desired clock div. Our initial analysis is all done at 50MHz, so clock_div = 1.
        configure_clock_ref(clk, 1);
        // Start the clock block running.
        start_clock(clk);
        
        unsigned toggle = 0;
        while(toggle < 10000) // Wait for 10000 consecutive 32 bit input words with transitions as a connector plug in debounce
        {
            p :> sample;
            if (cls(sample) < 32) // There was at least 1 transition on input
            {
                toggle++;
            }
            else
            {
                toggle = 0;
            }
        }
        
        clock_div = -1;
        while(clock_div == -1)
        {
            max_pulse = 0;
            for(int i=0; i<1000;i++) // 1000, 32 bit samples at 50MHz takes 640us.
            {
                p :> sample;
                raw_cls = cls(sample);
                if (raw_cls > max_pulse)
                {
                    max_pulse = raw_cls;
                }
            }
            
            if      ((max_pulse > 4 ) & (max_pulse < 11)) // 176.4/192kHz
            {
                clock_div = 0;
            }
            else if ((max_pulse > 11) & (max_pulse < 17)) // 88.2/96kHz
            {
                clock_div = 1;
            }
            else if ((max_pulse > 22) & (max_pulse < 32)) // 44.1/48kHz
            {
                clock_div = 2;
            }
        }
    
        // Stop clock so we can reconfigure it
        stop_clock(clk);
        
        // Set the desired clock div
        configure_clock_ref(clk, clock_div);
        
        int t_subframe_goal; 
        for(int j=0; j<2; j++) // Loop across two sample rate base options 44.1/48
        {
            
            if (j == 0) // All 44.1kHz based rates
            {
                for(int i=0; i<16;i++)
                {
                    unscramble[i] = unscramble_40201008[i] << 28;
                }
                t_add = 36;
                sample_mask = 0x40201008;
                pre_det_point = 25;
                t_subframe_goal = 283;
                z_pre_det_point = 28; // maybe adjust me, this was value for 48.
            }
            else // All 48kHz based rates
            {
                for(int i=0; i<16;i++)
                {
                    unscramble[i] = unscramble_10101010[i] << 28;
                }
                t_add = 33;
                sample_mask = 0x10101010;
                pre_det_point = 25; // was 24, changed to 25 and this reduced reception error rates - careful tho this could be due to a specific duty cycle error on this board. 24 means we see a preamble as ten bits or longer. 25 means 11 bits or longer.
                t_subframe_goal = 260;
                z_pre_det_point = 28;
            }

            // Start the clock block running. Port timer will be reset here.
            start_clock(clk);
            
            t = 100; // Set the time for the first read.

            // Initial lock to start of preambles and check our sampling freq is correct.
            // We will very quickly lock into one of two positions in the stream (where data transitions every 8UI)
            // This can happen in two places when you consider X and Y preambles and these are very frequent.
            // There is only one position we can lock when considering all three (X, Y and Z preambles) but waiting for Z preambles takes too long as only every 192 frames.
            // So we detect if we have locked to wrong transition and bump the time by 2UI (8 bits) to the correct transition.
            unsigned pre_count = 0;
            unsigned t_pre = 0;
            int t_subframe = 0;
            
            for(int i=0; i<200;i++)
            {
                // p @ t :> sample;
                // Manual setpt and in instruction since compiler generates an extra setc per IN (bug #15256)
                asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
                asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p)); 
                error = 18 - cls(sext(sample, 16)); // target is to have a transition between bits 13 and 14 - puts our samples symmetrically in the 32 bit sample.
                sample >>= error; // shift the sample to make the transition exactly between bits 13 and 14.
                if (cls(sext(sample, pre_det_point)) > 16) // Last two bits of old subframe and first half of preamble.
                {
                    pre_count++;
                    if (pre_count == 8)
                    {
                        t_pre = t;
                    }
                    else if (pre_count == 16)
                    {
                        t_subframe = t - t_pre;
                    }
                }
                if ((i == 50) && (pre_count < 4)) // If we've got to 50 inputs and still haven't locked to preamble boundary, we must be locked to other transition so bump us to the correct one.
                {
                    t += 8;
                }
                if (error < -3) // stop us running out of time for next input
                {
                    error = -3;
                }
                t += error + t_add;
            }
            
            // We can actually take a little bit of time here and do the next in after a whole subframe say.
            // Just need to add the calculated time for a subframe in local clocks before doing the next in.
            // t += (32.5*8) or whatever; we'll still be in lock. (clock can't drift much in one subframe).
            // If we didn't get lock or freq wrong, change to other receiver settings (44.1-48) and try again :)
            
            t_subframe = t_subframe >> 3; // Divide by 8 to get average subframe time.
            if (((t_subframe - t_subframe_goal) < 4) & ((t_subframe - t_subframe_goal) > -4)) // OK to start decoding
            {
                //printf("found valid input. pre_count = %d, t_subframe = %d, t_subframe_goal = %d, j = %d, clock_div = %d\n", pre_count, t_subframe, t_subframe_goal, j, clock_div);
                t += t_add;

                unsigned z_pre_n = 1;
                unsigned word_cnt = 0;
                unsigned pre_check;
                while(1)  // Main receive data loop.
                {
                    // p @ t :> sample;
                    // Manual setpt and in instruction since compiler generates an extra setc per IN (bug #15256)
                    asm volatile("setpt res[%0], %1"::"r"(p),"r"(t));
                    asm volatile("in %0, res[%1]" : "=r"(sample)  : "r"(p));
                    error = 18 - cls(sext(sample, 16)); // target is to have a transition between bits 13 and 14 - puts our samples symmetrically in the 32 bit sample.  Also note sign extend can be immediate if we use 1-8, 16, 24 or 32.
                    sample >>= error; // shift the sample to make the transition exactly between bits 13 and 14.
                    outword >>= 4;
                    outword |= unscramble[sample_and_compress(sample, sample_mask)];
                    pre_check = cls(sext(sample, pre_det_point));
                    if (pre_check == 32) // Too long a string of bits without a transition. This is our only exit out of the while(1).
                    {
                        break;
                    }
                    if (pre_check > 16) // Last two bits of old subframe and first half of preamble.
                    {
                        outword ^= (outword << 1);
                        outword = outword << 2;
                        outword |= z_pre_n; // or in the z preamble marker
                        outword = ~outword;
                        z_pre_n = 1;
                        c <: outword;
                    }
                    else if (cls(sext(sample, 13)) > z_pre_det_point) // Z preamble (in word with second half of preamble and first two bits of new subframe).
                    {
                        z_pre_n = 0;
                    }
                    t += error + t_add;
                }
            }
        }
    }
}
