
; jump table
defc jt_driver_init = 0xd000
defc jt_driver_queue_block = 0xd003
defc jt_driver_play_block = 0xd006

PUBLIC _sidplay_copy_driver
PUBLIC _sidplay_start
PUBLIC _sidplay_queue_block
PUBLIC _sid_file_base
PUBLIC _sid_file_length


SECTION code_user

_sidplay_copy_driver:
                jp copy_driver

_sidplay_start:
                pop af
                pop hl
                pop de
                push af
                push ix
                call jt_driver_init
                pop ix
                ret

_sidplay_queue_block:
                push ix
                call jt_driver_queue_block
                pop ix
                ret


copy_driver:
                ld hl, sid_driver_base
                ld de, 0xd000
                ld bc, sid_driver_end - sid_driver_base
                ldir
                ret

SECTION rodata_user

sid_driver_base:
               binary "sidplayer-driver__.bin"
defc sid_driver_end = $


sid_file_base:
               binary "Thing_On_A_Spring.sid"
defc sid_file_end = $

_sid_file_base:
                defw sid_file_base
_sid_file_length:
                defw sid_file_end - sid_file_base
