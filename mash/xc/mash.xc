#include <platform.h>
#include <stdio.h>

#define SAMPLE_COUNT 1024

void mash(void)
{
    unsigned ds_in = 0x828F6; // 20 bit unsigned modulator input

    int ds_out; // 8 level signed modulator output (-3 to +4).
    
    unsigned sum[3];
    unsigned q[3]  = {1,0,0}; // Odd number in q[0] reduces repeating patterns for a static input.
    unsigned d[3];
    unsigned c0, c1, c2;
    unsigned c1_d = 0;
    unsigned c2_d = 0;
    unsigned c2_d_d = 0;
    
    ds_in = ds_in & 0x000FFFFF; // make sure input limited to 20 bits.
    
    printf("ds_in 0x%05X\n", ds_in);

    for(int i = 0; i < SAMPLE_COUNT; i++)
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
        
        // Now implement the time delay elements
        // Error feedback flip flops
        q[0] = d[0];
        q[1] = d[1];
        q[2] = d[2];
        // Delayed Carry flip flops
        c2_d_d = c2_d;
        c2_d = c2;
        c1_d = c1;
        
        printf("%d\n", ds_out);
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
