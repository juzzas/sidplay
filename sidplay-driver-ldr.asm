
; jump table
defc jt_driver_init = 0xd000
defc jt_driver_queue_block = 0xd003
defc jt_driver_play_block = 0xd006

PUBLIC sidplay_loader


SECTION LOADER

sidplay_loader:
                ld hl, sid_driver_base
                ld de, 0xd000
                ld bc, sid_driver_end - sid_driver_base
                ldir
                ret

SECTION rodata_user

sid_driver_base:
               binary "sidplayer-driver__.bin"
defc sid_driver_end = $
