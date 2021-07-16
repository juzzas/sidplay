/*
 * RC2014 SID Interface player
 *
 * Copyright Justin Skists, 2021
 *
 * Summary:
 *  - Copies (currently embedded) .sid file to 0xC000 - 126
 *  - Copies driver to 0xD000 (possible conflict with CP/M)
 *  - sidplay_init generates 25frames worth of SID data blocks
 *  - sidplay_play_block plays one SID data block
 *  - sidplay_record_block generates one frame of SID data.
 *
 * TODO:
 *  - respond to buffer full/empty on play and record.
 *  - respond to error conditions from the 6510 execution
 *  - rename "record_block" to "execute_frame"
 *  - rename "play_block" to "play_frame"
 *  - introduce actual timer interrupts from Quazar SID interface
 *  - add "variable" in driver for interrupt frequency (0, 50, 60, 100Hz)
 *  - add function to get the address and size to copy the SID data
 *  - allow user to load files (or at least set pointer to where file header is), and copy actual binary (+126 bytes)
 *      to to the load address
 *  - remove old interrupt code from driver
 *  - Copy CP/M BDOS area and replace it later?
 *  - add visual demo! :)
 *      - Quazar OLED
 *      - RC2014 Bubble (minute/second counter?)
 *  - move SID data to another address, rather than 0xD400?
 */

#include <stdio.h>
#include <z80.h>

extern void sidplay_copy_driver();
extern void sidplay_copy_sidfile();
extern void sidplay_init();
extern void sidplay_record_block();
extern void sidplay_play_block();

int main(int argc, char **argv)
{
    int i;

    sidplay_copy_driver();
    sidplay_copy_sidfile();

    sidplay_init();

    while (1) {
        z80_delay_ms(20);  // 50Hz
        sidplay_play_block();

        for (i = 0; i < 8; i++) {
            sidplay_record_block();
        }
    }

    return 0;
}


