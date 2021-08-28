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

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "bubtb.h"
#include "sidplay-rc2014.h"
#include "sidplay-z88dk.h"

extern void sidplay_copy_driver();
extern void sidplay_copy_sidfile();

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
    FILE *fd;
    int rc;


    clear_buffer();
    flush_display_buffer();

#if 0
    fd = fopen("AIRWOLF.SID","rb");
    if (!fd) {
        printf("Can't open SID file\n");
        exit(1);
    }

    fread(S_sidfile_header, sizeof(S_sidfile_header), 1, fd);
#endif
    S_sidfile = (struct SidFileInfo *)sid_file_base;

    sid_raw = (uint8_t *)sid_file_base;
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
        load_addr = wpeek(&sid_raw[data_offset]);
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
#if 0
    for (i = 0; i < 8; i++)
        put_char_at_index(S_bubble_buffer[i], i);

    rc = fseek(fd, 0, SEEK_SET);
    if (rc != 0)
    {
        printf("Unable to seek to start of file");
        exit(1);
    }

    fseek(fd, 0, SEEK_END);
    long fsize = ftell(fd);
    printf("Length of file: 0x%lx\n", fsize);
    fseek(fd, 0, SEEK_SET);  /* same as rewind(f); */

    rc = fread((void *)0xa000, 1, fsize, fd);
    printf("file read rc: %d\n", rc);
    fclose(fd);
#endif

    __asm
    di
    __endasm;

    sidplay_copy_driver();
    sidplay_start(sid_file_base, sid_file_length);

    while (1) {
        sidplay_queue_block();
        // flush_display_buffer();
    }
    return 0;
}


