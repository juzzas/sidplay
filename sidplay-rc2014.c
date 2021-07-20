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
#include <stdlib.h>
#include <string.h>
#include <z80.h>

#include "bubtb.h"
#include "sidplay-rc2014.h"

extern void sidplay_copy_driver();
extern void sidplay_copy_sidfile();
extern void sidplay_init();
extern void sidplay_record_block();
extern void sidplay_play_block();

static struct SidFileInfo *S_sidfile;
static char S_name[33];
static char S_author[33];
static char S_released[33];

static char S_bubble_buffer[8 + 1] = "  cute  ";

uint16_t swap16(uint16_t val)
{
    uint16_t tmp;

    tmp = (val & 0x00ff) << 8;
    tmp |= (val & 0xff00) >> 8;

    return tmp;
}

void copy_sid_string(char *dest, char *source)
{
    memcpy(dest, source, 32);
    dest[32] = 0;
}


int main(int argc, char **argv)
{
    uint8_t *sid_raw;
    uint16_t version;
    uint16_t data_offset;
    uint16_t load_addr;
    int i;

    sidplay_copy_driver();
    //sidplay_copy_sidfile();

    clear_buffer();
    flush_display_buffer();

    S_sidfile = (struct SidFileInfo *)sid_file_base;

    sid_raw = (uint8_t *)S_sidfile;
    version = swap16(S_sidfile->version);
    data_offset = swap16(S_sidfile->data_offset);
    load_addr = swap16(S_sidfile->load_address);

    printf("sid file base = 0x%x\n", sid_file_base);
    printf("sid file base = 0x%p\n", S_sidfile);
    printf("version = 0x%x\n", version);
    printf("data = 0x%04x\n", data_offset);
    printf("load address = 0x%x\n", load_addr);

    if (S_sidfile->load_address == 0)
    {
        load_addr = z80_wpeek(&sid_raw[data_offset]);
        data_offset += 2;

        printf("real load address = 0x%x\n", load_addr);
        printf("real data offset = 0x%x\n", data_offset);
    }
    printf("init address = 0x%04x\n", swap16(S_sidfile->init_address));
    printf("play address = 0x%04x\n", swap16(S_sidfile->play_address));

    copy_sid_string(S_name, S_sidfile->name);
    copy_sid_string(S_author, S_sidfile->author);
    copy_sid_string(S_released, S_sidfile->released);

    printf("Name: %s\n", S_name);
    printf("Author: %s\n", S_author);
    printf("Released: %s\n", S_released);

    for (i = 0; i < 8; i++)
        put_char_at_index(S_bubble_buffer[i], i);


    /*
     * currently, just blat the whole lot to to load_address - offset
     * in future, well pass two pointers to the driver sid_header and sid data
     */
    memcpy ((void *)(load_addr - data_offset), sid_raw, sid_file_end - sid_file_base);


    sidplay_init();

    while (1) {
        sidplay_play_block();
        flush_display_buffer();
        //for (i = 0; i < 4; i++) {
            sidplay_record_block();
        //}
        z80_delay_ms(10);  // very approximate 50Hz
    }

    return 0;
}


