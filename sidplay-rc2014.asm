
; jump table
defc jt_driver_play_start = 0xd000
defc jt_driver_next_block = 0xd003

PUBLIC _sidplay_copy_driver
PUBLIC _sidplay_init
PUBLIC _sidplay_record_block
PUBLIC _sidplay_play_start
PUBLIC _sid_file_base
PUBLIC _sid_file_length


SECTION code_user

_sidplay_copy_driver:
                jp copy_driver

_sidplay_init:
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

_sidplay_play_enable:
                push ix
                call jt_driver_play_enable
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
_sid_file_lenght:
                defw sid_file_end - sid_file_base
