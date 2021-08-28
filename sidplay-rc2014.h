//
// Created by justin on 17/07/2021.
//

#ifndef SIDPLAY_RC2014_H
#define SIDPLAY_RC2014_H
#include "stdint.h"

struct SidFileInfo {
    char magic_id[4];        /* +00 */
    uint16_t version;        /* +04 */
    uint16_t data_offset;    /* +06 */
    uint16_t load_address;   /* +08 */
    uint16_t init_address;   /* +0a */
    uint16_t play_address;   /* +0c */
    uint16_t songs;          /* +0e */
    uint16_t start_song;     /* +10 */
    uint32_t speed;          /* +12 */
    char name[32];           /* +16 */
    char author[32];         /* +36 */
    char released[32];       /* +56 */
    uint16_t flags;          /* +76 - only on v2, v3, and v4 */
};


extern void *sid_file_base;
extern uint16_t sid_file_length;

#endif //SIDPLAY_RC2014_H
