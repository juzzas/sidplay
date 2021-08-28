//
// Created by justin on 10/07/2021.
//

#ifndef SIDPLAY_Z88DK_H
#define SIDPLAY_Z88DK_H

extern void sidplay_start(void *sid_file_base, uint16_t length) __z88dk_callee;
extern void sidplay_queue_block(void);

#endif //SIDPLAY_Z88DK_H
