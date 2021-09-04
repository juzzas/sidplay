

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


SECTION code_user


PUBLIC _main


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

        ld hl, oled_buffer
        call asm_oled_blit

        call sidplay_loader

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
        PUSH IX
        CALL asm_oled_glyph8_putc
        POP IX
        POP HL

        pop bc
        inc hl

        djnz output_sidstring_l1
        ret


loop:
	ld a, (ledval)
	out (0x00), a
	inc a
	ld (ledval), a
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

SECTION data_user

oled_buffer:
        DEFS 512

ledval:
	defb 0x01


