//
// Created by justin on 10/07/2021.
//

#ifndef SIDPLAY_Z88DK_H
#define SIDPLAY_Z88DK_H

extern void sidplay_init(void *sid_file_base, uint16_t length) __z88dk_callee;
extern void sidplay_record_block(void);
extern void sidplay_play_start(void);

#endif //SIDPLAY_Z88DK_H
