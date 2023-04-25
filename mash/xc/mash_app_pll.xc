#include <platform.h>
#include <syscall.h>
#include <xclib.h>
#include <print.h>
#include <assert.h>
#include <stdio.h>

//Found solution: IN 24.000MHz, OUT 24.576136MHz, VCO 2162.70MHz, RD  4, FD  360.450 (m =   9, n =  20), OD  2, FOD   11, ERR 5.549ppm
#define APP_PLL_CTL   0x08816703
#define APP_PLL_DIV   0x8000000A

// Fout = (Fin/4)*divider/(2*2*11*2) = (fin/352) * divider = (24/352) * divider.
// So absolute frequency span (divider to (divider + 1)) = 24/352 = 3/44 MHz.
// Total freq tune range = ((361/360) - 1) * 1000000 ppm = 2777.7ppm.
// Setting of 0 (0x00000) => Divide of 361. Output freq = (3/44) * 361 ~= 24.5454MHz. This is -1243ppm from ideal 24.576MHz.
// Setting of 1 (0xFFFFF) => Divide of 360. Output freq = (3/44) * 360 ~= 24.6136MHz. This is +1531ppm from ideal 24.576MHz.
// To achieve frequency f(MHz), Setting = ((44/3)*f) - 360
// So to achieve 24.576MHz, Setting = ((44/3)*24.576) - 360 = 0.448 (0x72B02)

// Set secondary (App) PLL control register safely to work around chip bug.
void set_app_pll_init (tileref tile, int app_pll_ctl)
{
    // Disable the PLL 
    write_node_config_reg(tile, XS1_SSWITCH_SS_APP_PLL_CTL_NUM, (app_pll_ctl & 0xF7FFFFFF));
    // Enable the PLL to invoke a reset on the appPLL.
    write_node_config_reg(tile, XS1_SSWITCH_SS_APP_PLL_CTL_NUM, app_pll_ctl);
    // Must write the CTL register twice so that the F and R divider values are captured using a running clock.
    write_node_config_reg(tile, XS1_SSWITCH_SS_APP_PLL_CTL_NUM, app_pll_ctl);
    // Now disable and re-enable the PLL so we get the full 5us reset time with the correct F and R values.
    write_node_config_reg(tile, XS1_SSWITCH_SS_APP_PLL_CTL_NUM, (app_pll_ctl & 0xF7FFFFFF));
    write_node_config_reg(tile, XS1_SSWITCH_SS_APP_PLL_CTL_NUM, app_pll_ctl);
    // Wait for PLL to lock.
    delay_microseconds(500);
}

void mash()
{
    unsigned ds_in = 0x72B02; // 20 bit
    int ds_out;
    
    unsigned sum[3];
    unsigned q[3]  = {1,0,0}; // Odd number in q[0] reduces spurs
    unsigned d[3];
    unsigned c0, c1, c2;
    unsigned c1_d = 0;
    unsigned c2_d = 0;
    unsigned c2_d_d = 0;
    unsigned pll_ctl_val;
    timer tmr;
    int t1 = 0;
    
    ds_in = ds_in & 0x000FFFFF; // make sure input limited to 20 bits.
    
    // Lets initialise the app PLL with default settings for ~24.576MHz
    // Initialise the AppPLL and get it running.
    set_app_pll_init (tile[0], APP_PLL_CTL);
    // And then write the clock divider register to enable the output
    write_node_config_reg(tile[0], XS1_SSWITCH_SS_APP_CLK_DIVIDER_NUM, APP_PLL_DIV);
    
    tmr :> t1; // Get the first time from the timer.
    while(1)
    {
        // MASH 1-1-1 modulator
        // Accumulator 1
        sum[0] = (q[0] + ds_in);
        d[0] = sum[0] & 0x000FFFFF; // Mask off carry bit, just keep bottom 20 bits.
        c0  = (sum[0] & 0x00100000) >> 20; // Extract carry bit
        // Accumulator 2
        sum[1] = (q[1] + d[0]);
        d[1] = sum[1] & 0x000FFFFF;
        c1  = (sum[1] & 0x00100000) >> 20;
        // Accumulator 3
        sum[2] = (q[2] + d[1]);
        d[2] = sum[2] & 0x000FFFFF;
        c2  = (sum[2] & 0x00100000) >> 20;
        
        // MASH Output
        ds_out = c0 + c1 - c1_d + c2 - (c2_d << 1) + c2_d_d; // Third order (MASH 1-1-1).
        
        //printf("ds_in %d, d[0] %d, d[1] %d, c0 %d, c1 %d, c1_d %d, ds_out %d, pll_ctl_val %08X\n", ds_in, d[0], d[1], c0, c1, c1_d, ds_out, pll_ctl_val);
        
        // Error feedback flip flops
        q[0] = d[0];
        q[1] = d[1];
        q[2] = d[2];
        // Delayed Carry flip flops
        c2_d_d = c2_d;
        c2_d = c2;
        c1_d = c1;
        
        // Add the MASH ds output into the PLL control word.
        pll_ctl_val = APP_PLL_CTL + (ds_out << 8);
        
        // This is the period that we are running the PLL control register write at. 200 io ref clocks = 2us.
        // This period must be an exact integer multiple of the PLL divided ref clock
        // This is defined by the PLL settings (to set the divider for the 24MHz ref clock).
        // The period is 1/divided ref clock
        // For this example, ref divder is 4, so divided ref clock is 24/4 = 6MHz.
        // so period is (1/6MHz) = 166.66ns.
        // In this case we've used a period of 2us which is exactly 12 divided ref clock cycles (166.66ns * 12 = 2us).
        t1 = t1 + 100; // We want to write reg every 2us.
        tmr when timerafter(t1) :> void;
        // Write the register. Because we are now timing the reg writes accurately we do not need to use reg write with ack. This saves a lot of time. Additionally, apparently we can shorten the time for this reg write by only setting up the channel once and just doing a few instructions to do the write each time. We can hard code this in assembler.
        write_node_config_reg_no_ack(tile[0], XS1_SSWITCH_SS_APP_PLL_CTL_NUM, pll_ctl_val);
    }
}

int main()
{
    par
    {
        on tile[0]: mash();
    }

    return 0;
}
