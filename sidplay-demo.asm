

; Copyright 2021 Justin Skists
;
; Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
; documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
; rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
; persons to whom the Software is furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
; Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
; WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
; COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
; OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


SECTION MAIN


PUBLIC _main

EXTERN addr_loop_callback
EXTERN addr_frame_callback

EXTERN standalone_sid_file_base
EXTERN standalone_sid_file_length

EXTERN sidplay_loader

EXTERN asm_oled_init
EXTERN asm_oled_blit_init
EXTERN asm_oled_blit
EXTERN asm_oled_glyph8_putc
EXTERN asm_oled_glyph8_puts
EXTERN oled_glyph8_std_font4
EXTERN test_buffer



DEFC sidplay_start = 0xd000
DEFC BUFFER_SIZE= 512
DEFC OLED_WIDTH = 128

_main:
        di

        call asm_oled_init
        call asm_oled_blit_init

        ld a, 0x00
        call memset_buffer

        ld hl, oled_buffer
        call asm_oled_blit

        LD IX, oled_glyph8_std_font4
        ld b, 4   ; font width
        LD C, 0   ; line offset

        LD DE, oled_buffer
        LD IX, oled_glyph8_std_font4
        ld b, 4   ; font width
        LD C, 0   ; line offset
        ld hl, text_name
        call asm_oled_glyph8_puts

        LD DE, oled_buffer+40
        LD IX, oled_glyph8_std_font4
        ld b, 4   ; font width
        LD C, 0   ; line offset
        ld hl, standalone_sid_file_base+0x16   ; name field
        call output_sidstring

        ;; author
        LD DE, oled_buffer+OLED_WIDTH
        LD IX, oled_glyph8_std_font4
        ld b, 4   ; font width
        LD C, 0   ; line offset
        ld hl, text_author
        call asm_oled_glyph8_puts

        LD DE, oled_buffer+OLED_WIDTH+40
        LD IX, oled_glyph8_std_font4
        ld b, 4   ; font width
        LD C, 0   ; line offset
        ld hl, standalone_sid_file_base+0x36   ; author field
        call output_sidstring

        ;; released
        LD DE, oled_buffer+OLED_WIDTH+OLED_WIDTH
        LD IX, oled_glyph8_std_font4
        ld b, 4   ; font width
        LD C, 0   ; line offset
        ld hl, text_released
        call asm_oled_glyph8_puts

        LD DE, oled_buffer+OLED_WIDTH+OLED_WIDTH+40
        LD IX, oled_glyph8_std_font4
        ld b, 4   ; font width
        LD C, 0   ; line offset
        ld hl, standalone_sid_file_base+0x56   ; released field
        call output_sidstring


        call output_timer


        ld hl, oled_buffer
        call asm_oled_blit

        call sidplay_loader

        ld hl, demo_frame_callback
        ld (addr_frame_callback), hl

        ld hl, demo_loop_callback
        ld (addr_loop_callback), hl

        ld hl, standalone_sid_file_base
        ld de, standalone_sid_file_length
        call sidplay_start

        ; display return value
        ld a, c
        out (0x00), a

        ret

output_sidstring:
        ld b, 32

output_sidstring_l1:
        ld a, (hl)
        and a
        ret z

        push bc
        ld b, 4   ; font width
        LD C, 0   ; line offset

        PUSH HL
        CALL asm_oled_glyph8_putc
        POP HL

        pop bc
        inc hl

        djnz output_sidstring_l1
        ret

output_timer:
        LD DE, oled_buffer+OLED_WIDTH+OLED_WIDTH+OLED_WIDTH+64
        LD IX, oled_numerals

        LD A, (minutes)
        AND 0x0f
        call putc_nibble

        LD C, 0  ; line offset
        LD A, 13
        call asm_oled_glyph8_putc


        LD A, (seconds)   ; high nibble
        SRL A
        SRL A
        SRL A
        SRL A
        call putc_nibble

        LD A, (seconds)    ; low nibble
        AND 0x0f
        call putc_nibble

        LD A, 12
        LD C, 0  ; line offset
        call asm_oled_glyph8_putc

        RET

; entry a:= 0-9
putc_nibble:
        ld B, 8   ; font width
        LD C, 0x80  ; line offset + print wide
        call asm_oled_glyph8_putc
        RET

demo_frame_callback:
        ld a, (ledval)
        out (0x00), a
        inc a
        ld (ledval), a

        ld a, (frames)
        inc a
        cp 50    ; todo: 60/100 Hz tunes...
        jr z,inc_seconds
        ld (frames), a
        ret

inc_seconds:
        ld a, 0
        ld (frames), a
        ld a, (seconds)
        inc a
        daa
        cp 0x60
        jr z, inc_minutes
        ld (seconds), a
        ret

inc_minutes:
        ld a, 0
        ld (seconds), a
        ld a, (minutes)
        inc a
        daa
        ld (minutes), a
        ret


demo_loop_callback:
        ld a, (seconds)
        ld l, a
        ld a, (old_seconds)
        cp l
        ret z

        ld a, l
        ld (old_seconds), a

        call output_timer
        ld hl, oled_buffer
        call asm_oled_blit
        ret


; entry: A= data to set buffer
memset_buffer:
        LD HL, oled_buffer
        LD (HL), A
        LD DE, HL
        INC DE
        LD BC, BUFFER_SIZE-1
        LDIR
        RET

SECTION rodata_user

text_name:
        DEFM "Name: ", 0

text_author:
        DEFM "Author: ", 0

text_released:
        DEFM "Released: ", 0

PUBLIC oled_numerals


;; 0123456789:."'-/

oled_numerals:
        DEFB  0x00, 0x00, 0x7e, 0x42, 0x42, 0x42, 0x7e, 0x00, 0x00, 0x00, 0x00, 0x02
        DEFB  0x7e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x72, 0x52, 0x52, 0x52, 0x5e, 0x00
        DEFB  0x00, 0x00, 0x42, 0x52, 0x52, 0x52, 0x7e, 0x00, 0x00, 0x00, 0x1e, 0x10
        DEFB  0x10, 0x10, 0x7e, 0x00, 0x00, 0x00, 0x5e, 0x52, 0x52, 0x52, 0x72, 0x00
        DEFB  0x00, 0x00, 0x7e, 0x52, 0x52, 0x52, 0x72, 0x00, 0x00, 0x00, 0x02, 0x02
        DEFB  0x62, 0x1a, 0x06, 0x00, 0x00, 0x00, 0x7e, 0x4a, 0x4a, 0x4a, 0x7e, 0x00
        DEFB  0x00, 0x00, 0x5e, 0x52, 0x52, 0x52, 0x7e, 0x00, 0x00, 0x00, 0x00, 0x00
        DEFB  0x24, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00
        DEFB  0x00, 0x00, 0x00, 0x06, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        DEFB  0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x10, 0x10, 0x10, 0x00, 0x00
        DEFB  0x00, 0x00, 0x00, 0x60, 0x18, 0x06, 0x00, 0x00


SECTION data_user

oled_buffer: DEFS 512

minutes: DEFB 0
seconds: DEFB 0

old_seconds: DEFB 0
frames: DEFB 0

ledval:
	defb 0x01


