
; jump table
defc jt_driver_init = 0xd000
defc jt_driver_queue_block = 0xd003
defc jt_driver_play_block = 0xd006

PUBLIC _sidplay_start


SECTION code_user

_sidplay_start:
                di

                pop af
                pop hl   ;; sid file base
                pop de   ;; sid file length

                exx

;; copy_driver
                ld hl, sid_driver_base
                ld de, 0xd000
                ld bc, sid_driver_end - sid_driver_base
                ldir

                exx

                jp jt_driver_init

                ; don't expect to come back home....

SECTION rodata_user

sid_driver_base:
               binary "sidplayer-driver__.bin"
defc sid_driver_end = $
