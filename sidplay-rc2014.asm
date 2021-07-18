
; jump table
defc jt_driver_init = 0xd000
defc jt_driver_record_block = 0xd003
defc jt_driver_play_block = 0xd006

PUBLIC _sidplay_copy_driver
PUBLIC _sidplay_copy_sidfile
PUBLIC _sidplay_init
PUBLIC _sidplay_record_block
PUBLIC _sidplay_play_block
PUBLIC _sid_file_base
PUBLIC _sid_file_end


SECTION code_user

_sidplay_copy_driver:
                jp copy_driver

_sidplay_copy_sidfile:
                jp copy_sidfile

_sidplay_init:
                push af
                push bc
                push de
                push hl
                push ix
                call jt_driver_init
                pop ix
                pop hl
                pop de
                pop bc
                pop af
                ret

_sidplay_record_block:
                push af
                push bc
                push de
                push hl
                push ix
                call jt_driver_record_block
                pop ix
                pop hl
                pop de
                pop bc
                pop af
                ret

_sidplay_play_block:
                push af
                push bc
                push de
                push hl
                push ix
                call jt_driver_play_block
                pop ix
                pop hl
                pop de
                pop bc
                pop af
                ret




copy_driver:
                ld hl, sid_driver_base
                ld de, 0xd000
                ld bc, sid_driver_end - sid_driver_base
                ldir
                ret

copy_sidfile:
               ; position SID tune player code at 0xc000
               ; this is the known load address for Thing on a Spring
                ld hl, sid_file_base
                ld de, 0xc000 - 126
                ld bc, sid_file_end - sid_file_base
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
_sid_file_end:
                defw sid_file_end
