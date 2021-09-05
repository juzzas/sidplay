
; jump table
defc jt_driver_init = 0xd000

defc default_song = 0xd003     ; 0=default song from SID header
defc addr_loop_callback = 0xd004
defc addr_frame_callback = 0xd006

PUBLIC sidplay_loader

PUBLIC default_song
PUBLIC addr_loop_callback
PUBLIC addr_frame_callback

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
