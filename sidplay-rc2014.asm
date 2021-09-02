
; jump table
defc jt_driver_init = 0xd000
defc jt_driver_queue_block = 0xd003
defc jt_driver_play_block = 0xd006

PUBLIC _sidplay_start
PUBLIC _sid_file_base
PUBLIC _sid_file_length


SECTION code_user

_sidplay_start:
                pop af
                pop hl   ;; sid file base
                pop de   ;; sid file length

                ld sp, my_stack
                push de
                push hl

                call copy_driver

                pop hl
                pop de

                call jt_driver_init

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
               ;binary "Thing_On_A_Spring.sid"
               binary "Yie_Ar_Kung_Fu.sid"
defc sid_file_end = $

_sid_file_base:
                defw sid_file_base
_sid_file_length:
                defw sid_file_end - sid_file_base


SECTION data_user

                defs 32
defc my_stack = $
