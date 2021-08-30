; SID Player Driver, by Justin Skists
; Based heavily on SID Player v1.5, by Simon Owen
;
; https://github.com/simonowen/sidplay
;
; Emulates a 6510 CPU to play a C64 SID tunes in real time.
; Requires ZX Spectrum SID interface using ports xxCF
;
; RANDOMIZE USR 53248 to play sample tune (Thing on a Spring)
; POKE &d002,tune-number (default=0, for SID default)
; POKE &d003,key-mask (binary: 0,0,Esc,Right,Left,Down,Up,Space)
; DPOKE &d004,pre-buffer-frames (default=25, for 0.5 seconds)
;
; Features:
;   - Full 6510 emulation in Z80
;   - PAL (50Hz) playback speed only
;   - Both polled and timer-driven players
;
; RSID files and sound samples are not supported.

; Record_block places a bunch of SID register writes (in blocks of 32bytes) to the buffer (0xa000 to 0xb000)
; play block retreives the next buffer and plays it.

defc base          =  0xd000           ; Player based at 53248

defc buffer_blocks =  25              ; number of frames to pre-buffer

defc rc2014_sid_port   =  0x54             ; base port for SID interface
defc rc2014_dbg_port   =  0x00             ; base port for LED output

defc zero_page_msb =  0xe0             ; 6502 zero page base MSB
defc stack_msb     =  0xe1             ; 6502 stack base MSB

defc border        =  254             ; Bits 3-0 hold border colour (output)
defc keyboard      =  254             ; Keyboard matrix (input)

defc ret_ok        =  0               ; no error (space to exit)
defc ret_space     =  ret_ok          ; space
defc ret_up        =  1               ; cursor up
defc ret_down      =  2               ; cursor down
defc ret_left      =  3               ; cursor left
defc ret_right     =  4               ; cursor right
defc ret_esc       =  5               ; esc
defc ret_badfile   =  6               ; missing or invalid file
defc ret_rsid      =  7               ; RSID files unsupported
defc ret_timer     =  8               ; unsupported timer frequency
defc ret_irq       =  9               ; unsupported irq handler

defc c64_cia_timer =  0xdc04           ; C64 CIA#1 timer
defc c64_sid_base  =  0xd400           ; C64 SID chip

defc z80_ret_op    =  0xc9             ; RET opcode

defc sid_file_base_default = 0xa000

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SECTION MAIN
; jump table
hook_driver_start:
               jp   start

hook_driver_queue_block:
               jp   play_loop  ;record_block

hook_driver_play_block:
               jp   play_block

sid_file_base: defw sid_file_base_default
sid_file_len:  defw 0
song:          defb 0               ; 0=default song from SID header
key_mask:      defb %00000000       ; exit keys to ignore
pre_buffer:    defw buffer_blocks   ; pre-buffer 1 second


;; SIOD DRIVER START
;; Entry:
;;     HL = SID file base addres
;;     DE = SID file length
start:         di

               ld   (old_stack+1),sp
               ld   sp,new_stack

               ld a, 0x01
               out (rc2014_dbg_port), a

init:
               ld (sid_file_base), hl
               ld (sid_file_len), de

               ld   a,(hl)
               cp   'R'             ; RSID signature?
               ld   c,ret_rsid
               jp   z,exit_player
               cp   'P'             ; new PSID signature?
               jr   nz,old_file

               ld   de,sid_header
               ld   bc,22
               ldir                 ; copy header to master copy
old_file:      ex   af,af'          ; save Z flag for new file

               ld   ix,sid_header
               ld   a,(ix)
               cp   'P'
               ld   c,ret_badfile
               jp   nz,exit_player

               ld   h,(ix+10)       ; init address
               ld   l,(ix+11)
               ld   (init_addr),hl
               ld   h,(ix+12)       ; play address
               ld   l,(ix+13)
               ld   (play_addr),hl

               ld   h,(ix+6)        ; data offset (big-endian)
               ld   l,(ix+7)
               ld   d,(ix+8)        ; load address (or zero)
               ld   e,(ix+9)

               ld   a,d
               or   e
               jr   nz,got_load     ; jump if address valid
               ld   de,(sid_file_base)
               add  hl, de
               ld   e,(hl)          ; take address from start of data
               inc  hl               ; (already little endian)
               ld   d,(hl)
               inc  hl
got_load:

               ex   af,af'
               jr   nz,no_reloc

; At this point we have:  HL=sid_data DE=load_addr
               ; Note: if load address is above sid_file_base, then we really should use lddr,
               ; just incase the two memory buffers overlap
               ld   bc, (sid_file_len)
               ldir

no_reloc:
               xor  a
               ld   h,zero_page_msb
               ld   l,a
clear_zp:      ld   (hl),a
               inc  l
               jr   nz,clear_zp

               ld   b,(ix+15)       ; songs available
               ld   c,(ix+17)       ; default start song
               ld   a,(song)        ; user requested song
               and  a               ; zero?
               jr   z,use_default   ; use default if so
               inc  b               ; max+1
               cp   b               ; song in range?
               jr   c,got_song      ; use if it is
use_default:   ld   a,c
got_song:      ld   (play_song),a   ; save song to play

               ld   hl,sid_header+21  ; end of speed bit array
speed_lp:      ld   c,1             ; start with bit 0
speed_lp2:     dec  a
               jr   z,got_speed
               rl   c               ; shift up bit to check
               jr   nc,speed_lp2
               dec  hl
               jr   speed_lp
got_speed:     ld   a,(hl)
               and  c
               ld   (ntsc_tune),a

               call sid_reset
               call play_tune

               ret



exit_player:   ld b,0
old_stack:     ld   sp,0
               ei
               ret

sid_header:    defs 22              ; copy of start of SID header

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Tune player

play_tune:     ld   hl,0
               ld   (blocks),hl     ; no buffered blocks
               ld   (c64_cia_timer),hl  ; no timer frequency
               ld   h,0xa0
               ld   (head),hl       ; head/tail at buffer start
               ld   (tail),hl

               call reorder_decode  ; optimise decode table

               ld   a,(play_song)   ; song to play
               dec  a               ; player expects A=song-1
               ld   hl,(init_addr)  ; tune init function
               call execute         ; initialise player
               and  a
               ret  nz              ; return any error

               call record_block    ; record initial SID state

               ld   hl,(play_addr)  ; tune player poll address
               ld   a,h
               or   l
               jr   nz,buffer_loop  ; non-zero means we have one

               ld   a,ret_irq       ; no IRQ handler support yet
               ret

buffer_loop:   ld   hl,(blocks)     ; current block count
               ld   de,(pre_buffer) ; blocks to pre-buffer
               and  a
               sbc  hl,de
               jr   nc,buffer_done

               xor  a
               ld   hl,(play_addr)  ; poll or interrupt addr
               call execute
               and  a
               ret  nz              ; return any errors

               call record_block    ; record the state
               jr   buffer_loop     ; loop buffering more

buffer_done:   call check_speed     ; check for compatible playback speed
               call enable_player   ; enable interrupt-driven player

sleep_loop:    halt                 ; wait for a block to play

play_loop:
               ld   hl,(blocks)     ; check buffered blocks
               ld   de,4096/32-1    ; maximum we can buffer
               and  a
               sbc  hl,de
               jr   nc,sleep_loop   ; jump back to wait if full

               xor  a
               ld   hl,(play_addr)
               call execute         ; execute 1 frame
               and  a               ; execution error?
               ret  nz              ; return if so

               call record_block    ; record the new SID state
               jp   play_loop       ; generate more data

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; 6510 emulation

execute:       ex   de,hl           ; PC stays in DE throughout
               ld   iy,0            ; X=0, Y=0
               ld   ix,main_loop    ; decode loop after non-read/write

               ld   b,a             ; set A from Z80 A
               xor  a               ; clear carry
               ld   c,a             ; set Z, clear N
               ex   af,af'

               exx
               ld   h,stack_msb     ; 6502 stack pointer in HL'
               ld   l,0xff           ; top of stack
               ld   d,%00000100     ; interrupts disabled
               ld   e,0             ; clear V
               exx

read_write_loop:
write_loop:    ld   a,h
               cp   c64_sid_base/256 ; SID write to 0xd4xx?
               jr   z,sid_write

main_loop:     ld   a,(de)          ; fetch opcode
               inc  de              ; PC=PC+1
               ld   l,a
               ld   h,decode_table/256
               ld   a,(hl)          ; handler low
               inc  h
               ld   h,(hl)          ; handler high
               ld   l,a
               jp   (hl)            ; execute!

sid_write:     ld   a,(hl)
               set  6,l
               xor  (hl)
               jr   z,main_loop
               res  6,l
               set  5,l
               or   (hl)
               ld   (hl),a
               res  5,l
               ld   a,(hl)
               set  6,l
               ld   (hl),a
               jp   (ix)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Interrupt handling

SECTION INT

im2_table:     defs 257             ; 256 overlapped WORDs

im2_handler:   push af
               push bc
               push de
               push hl
               push ix

               ld a, 0x80
               out (rc2014_dbg_port), a

               call play_block

               pop  ix
               pop  hl
               pop  de
               pop  bc
int_exit:      pop  af
               ei
               reti

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Instruction implementations

defc i_nop = main_loop
defc i_undoc_1 =  main_loop
i_undoc_3:     inc  de              ; 3-byte NOP
i_undoc_2:     inc  de              ; 2-byte NOP
               jp   (ix)


i_bpl:         inc  c
               dec  c
               jp   p,i_branch      ; branch if plus
               inc  de
               jp   (ix)

i_bmi:         inc  c
               dec  c
               jp   m,i_branch      ; branch if minus
               inc  de
               jp   (ix)

i_bvc:         exx
               bit  6,e
               exx
               jr   z,i_branch      ; branch if V clear
               inc  de
               jp   (ix)

i_bvs:         exx
               bit  6,e
               exx
               jr   nz,i_branch     ; branch if V set
               inc  de
               jp   (ix)

i_bcc:         ex   af,af'
               jr   nc,i_branch_ex  ; branch if C clear
               ex   af,af'
               inc  de
               jp   (ix)

i_bcs:         ex   af,af'
               jr   c,i_branch_ex   ; branch if C set
               ex   af,af'
               inc  de
               jp   (ix)

i_beq:         inc  c
               dec  c
               jr   z,i_branch      ; branch if zero
               inc  de
               jp   (ix)

i_bne:         inc  c
               dec  c
               jr   nz,i_branch     ; branch if not zero
               inc  de
               jp   (ix)

i_branch_ex:   ex   af,af'
i_branch:      ld   a,(de)
               inc  de
               ld   l,a             ; offset low
               rla                  ; set carry with sign
               sbc  a,a             ; form high byte for offset
               ld   h,a
               add  hl,de           ; PC=PC+e
               ex   de,hl
               jp   (ix)


i_jmp_a:       ex   de,hl           ; JMP nn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               jp   (ix)

i_jmp_i:       ex   de,hl           ; JMP (nn)
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               ex   de,hl
               ld   e,(hl)
               inc  l               ; 6502 bug wraps within page, *OR*
;              inc  hl              ; 65C02 spans pages correctly
               ld   d,(hl)
               jp   (ix)

i_jsr:         ex   de,hl           ; JSR nn
               ld   e,(hl)          ; subroutine low
               inc  hl              ; only 1 inc - we push ret-1
               ld   d,(hl)          ; subroutine high
               ld   a,h             ; PCh
               exx
               ld   (hl),a          ; push ret-1 high byte
               dec  l               ; S--
               exx
               ld   a,l             ; PCl
               exx
               ld   (hl),a          ; push ret-1 low byte
               dec  l               ; S--
               exx
               jp   (ix)

i_brk: ; fall through
i_rts:         exx                  ; RTS
               inc  l               ; S++
               ld   a,ret_ok
               ret  z               ; finish if stack empty
               ld   a,(hl)          ; PC LSB
               exx
               ld   e,a
               exx
               inc  l               ; S++
               ld   a,(hl)          ; PC MSB
               exx
               ld   d,a
               inc  de              ; PC++ (strange but true)
               jp   (ix)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; C64 I/O range

SECTION C64_IO

; C64 SID register go here, followed by a second set recording changes
sid_regs:      defs 32
sid_changes:   defs 32
prev_regs:     defs 32
last_regs:     defs 32              ; last values written to SID

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

i_clc:         and  a               ; clear carry
               ex   af,af'
               jp   (ix)

i_sec:         scf                  ; set carry
               ex   af,af'
               jp   (ix)

i_cli:         exx                  ; clear interrupt disable
               res  2,d
               exx
               jp   (ix)

i_sei:         exx                  ; set interrupt disable
               set  2,d
               exx
               jp   (ix)

i_clv:         exx                  ; clear overflow
               ld   e,0
               exx
               jp   (ix)

i_cld:         exx                  ; clear decimal mode
               res  3,d
               exx
               xor  a               ; NOP
               ld   (adc_daa),a     ; use binary mode for adc
               ld   (sbc_daa),a     ; use binary mode for sbc
               jp   (ix)

i_sed:         exx                  ; set decimal mode
               set  3,d
               exx
               ld   a,0x27           ; DAA
               ld   (adc_daa),a     ; use decimal mode for adc
               ld   (sbc_daa),a     ; use decimal mode for sbc
               jp   (ix)


i_rti:         exx
               inc  l               ; S++
               ld   a,ret_ok
               ret  z               ; finish if stack empty
               ld   a,(hl)          ; pop P
               ld   c,a             ; keep safe
               and  %00001100       ; keep D and I
               or   %00110000       ; force T and B
               ld   d,a             ; set P
               ld   a,c
               and  %01000000       ; keep V
               ld   e,a             ; set V
               ld   a,c
               rra                  ; carry from C
               ex   af,af'          ; set carry
               ld   a,c
               and  %10000010       ; keep N Z
               xor  %00000010       ; zero for Z
               exx
               ld   c,a             ; set N Z
               exx
               inc  l               ; S++
               ld   a,(hl)          ; pop return LSB
               exx
               ld   e,a             ; PCL
               exx
               inc  l               ; S++
               ld   a,(hl)          ; pop return MSB
               exx
               ld   d,a             ; PCH
               ex   af,af'
               inc  l               ; S++
               ld   a,(hl)          ; pop return MSB
               exx
               ld   d,a
               ex   af,af'
               ld   e,a
               pop  af              ; restore from above
               ex   af,af'          ; set A and flags
               jp   (ix)


i_php:         ex   af,af'          ; carry
               inc  c
               dec  c               ; set N Z
               push af              ; save flags
               ex   af,af'          ; protect carry
               exx
               pop  bc
               ld   a,c
               and  %10000001       ; keep Z80 N and C
               bit  6,c             ; check Z80 Z
               jr   z,php_nonzero
               or   %00000010       ; set Z
php_nonzero:   or   e               ; merge V
               or   d               ; merge T D I
               or   %00010000       ; B always pushed as 1
               ld   (hl),a
               dec  l               ; S--
               exx
               jp   (ix)

i_plp:         exx
               inc  l               ; S++
               ld   a,(hl)          ; pop P
               ld   c,a             ; keep safe
               and  %00001100       ; keep D and I
               or   %00110000       ; force T and B
               ld   d,a             ; set P
               ld   a,c
               and  %01000000       ; keep V
               ld   e,a             ; set V
               ld   a,c
               rra                  ; carry from C
               ex   af,af'          ; set carry
               ld   a,c
               and  %10000010       ; keep N Z
               xor  %00000010       ; zero for Z
               exx
               ld   c,a             ; set N Z
               jp   (ix)

i_pha:         ld   a,b             ; A
               exx
               ld   (hl),a          ; push A
               dec  l               ; S--
               exx
               jp   (ix)

i_pla:         exx                  ; PLA
               inc  l               ; S++
               ld   a,(hl)          ; pop A
               exx
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix)


i_dex:         dec  iyh             ; X--
               ld   c,iyh           ; set N Z
               jp   (ix)

i_dey:         dec  iyl             ; Y--
               ld   c,iyl           ; set N Z
               jp   (ix)

i_inx:         inc  iyh             ; X++
               ld   c,iyh           ; set N Z
               jp   (ix)

i_iny:         inc  iyl             ; Y++
               ld   c,iyl           ; set N Z
               jp   (ix)


i_txa:         ld   b,iyh           ; A=X
               ld   c,b             ; set N Z
               jp   (ix)

i_tya:         ld   b,iyl           ; A=Y
               ld   c,b             ; set N Z
               jp   (ix)

i_tax:         ld   iyh,b           ; X=A
               ld   c,b             ; set N Z
               jp   (ix)

i_tay:         ld   iyl,b           ; Y=A
               ld   c,b             ; set N Z
               jp   (ix)

i_txs:         ld   a,iyh           ; X
               exx
               ld   l,a             ; set S (no flags set)
               exx
               jp   (ix)

i_tsx:         exx
               ld   a,l             ; S
               exx
               ld   iyh,a           ; X=S
               ld   c,a             ; set N Z
               jp   (ix)


i_lda_ix:      ld   a,(de)          ; LDA ($nn,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; zread_loop

i_lda_z:       ld   a,(de)          ; LDA $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; zread_loop

i_lda_a:       ex   de,hl           ; LDA $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; read_loop

i_lda_iy:      ld   a,(de)          ; LDA ($nn),Y
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               adc  a,h
               sub  l
               ld   h,a
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; read_loop

i_lda_zx:      ld   a,(de)          ; LDA $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; zread_loop

i_lda_ay:      ld   a,(de)          ; LDA $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; read_loop

i_lda_ax:      ld   a,(de)          ; LDA $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; read_loop

i_lda_i:       ld   a,(de)          ; LDA #$nn
               inc  de
               ld   b,a             ; set A
               ld   c,b             ; set N Z
               jp   (ix)


i_ldx_z:       ld   a,(de)          ; LDX $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   c,(hl)          ; set N Z
               ld   iyh,c           ; set X
               jp   (ix) ; zread_loop

i_ldx_a:       ex   de,hl           ; LDX $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   c,(hl)          ; set N Z
               ld   iyh,c           ; set X
               jp   (ix) ; read_loop

i_ldx_zy:      ld   a,(de)          ; LDX $nn,Y
               inc  de
               add  a,iyl           ; add Y (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   c,(hl)          ; set N Z
               ld   iyh,c           ; set X
               jp   (ix) ; zread_loop

i_ldx_ay:      ld   a,(de)          ; LDX $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   c,(hl)          ; set N Z
               ld   iyh,c           ; set X
               jp   (ix) ; read_loop

i_ldx_i:       ld   a,(de)          ; LDX #$nn
               inc  de
               ld   iyh,a           ; set X
               ld   c,a             ; set N Z
               jp   (ix)


i_ldy_z:       ld   a,(de)          ; LDY $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   c,(hl)          ; set N Z
               ld   iyl,c           ; set Y
               jp   (ix) ; zread_loop

i_ldy_a:       ex   de,hl           ; LDY $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   c,(hl)          ; set N Z
               ld   iyl,c           ; set Y
               jp   (ix) ; read_loop

i_ldy_zx:      ld   a,(de)          ; LDY $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   c,(hl)          ; set N Z
               ld   iyl,c           ; set Y
               jp   (ix) ; zread_loop

i_ldy_ax:      ld   a,(de)          ; LDY $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   c,(hl)          ; set N Z
               ld   iyl,c           ; set Y
               jp   (ix) ; read_loop

i_ldy_i:       ld   a,(de)          ; LDY #$nn
               inc  de
               ld   c,a             ; set N Z
               ld   iyl,c           ; set Y
               jp   (ix)


i_sta_ix:      ld   a,(de)          ; STA ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               ld   (hl),b          ; store A
               jp   (ix) ; zwrite_loop

i_sta_z:       ld   a,(de)          ; STA $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   (hl),b          ; store A
               jp   (ix) ; zwrite_loop

i_sta_iy:      ld   a,(de)          ; STA ($nn),Y
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l
               ld   h,(hl)
               ld   l,a
               adc  a,h
               sub  l
               ld   h,a
               ld   (hl),b          ; store A
               jp   write_loop

i_sta_zx:      ld   a,(de)          ; STA $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   (hl),b          ; store A
               jp   (ix) ; zwrite_loop

i_sta_ay:      ld   a,(de)          ; STA $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   (hl),b          ; store A
               jp   write_loop

i_sta_ax:      ld   a,(de)          ; STA $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   (hl),b          ; store A
               jp   write_loop

i_sta_a:       ex   de,hl           ; STA $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   (hl),b          ; store A
               jp   write_loop


i_stx_z:       ld   a,(de)          ; STX $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   a,iyh           ; X
               ld   (hl),a
               jp   (ix) ; zwrite_loop

i_stx_zy:      ld   a,(de)          ; STX $nn,Y
               inc  de
               add  a,iyl           ; add Y (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   a,iyh           ; X
               ld   (hl),a
               jp   (ix) ; zwrite_loop

i_stx_a:       ex   de,hl           ; STX $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   a,iyh           ; X
               ld   (hl),a
               jp   write_loop


i_sty_z:       ld   a,(de)          ; STY $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   a,iyl           ; Y
               ld   (hl),a
               jp   (ix) ; zwrite_loop

i_sty_zx:      ld   a,(de)          ; STY $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   a,iyl           ; Y
               ld   (hl),a
               jp   (ix) ; zwrite_loop

i_sty_a:       ex   de,hl           ; STY $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   a,iyl           ; Y
               ld   (hl),a
               jp   write_loop


i_stz_zx:      ld   a,(de)          ; STZ $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   (hl),h
               jp   (ix) ; zwrite_loop

i_stz_ax:      ld   a,(de)          ; STZ $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   (hl),0
               jp   write_loop

i_stz_a:       ex   de,hl           ; STZ $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   (hl),0
               jp   write_loop


i_adc_ix:      ld   a,(de)          ; ADX ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               jp   i_adc

i_adc_z:       ld   a,(de)          ; ADC $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               jp   i_adc

i_adc_a:       ex   de,hl           ; ADC $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               jp   i_adc

i_adc_zx:      ld   a,(de)          ; ADC $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               jp   i_adc

i_adc_ay:      ld   a,(de)          ; ADC $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               jp   i_adc

i_adc_ax:      ld   a,(de)          ; ADC $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               jp   i_adc

i_adc_iy:      ld   a,(de)          ; ADC ($nn),Y
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               adc  a,h
               sub  l
               ld   h,a
               jp   i_adc

i_adc_i:       ld   h,d
               ld   l,e
               inc  de
i_adc:         ex   af,af'          ; carry
               ld   a,b             ; A
               adc  a,(hl)          ; A+M+C
adc_daa:       nop
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               exx
               jp   pe,adcsbc_v
               ld   e,%00000000
               exx
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop
adcsbc_v:      ld   e,%01000000
               exx
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop


i_sbc_ix:      ld   a,(de)          ; SBC ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               jp   i_sbc

i_sbc_z:       ld   a,(de)          ; SBC $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               jp   i_sbc

i_sbc_a:       ex   de,hl           ; SBC $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               jp   i_sbc

i_sbc_zx:      ld   a,(de)          ; SBC $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               jp   i_sbc

i_sbc_ay:      ld   a,(de)          ; SBC $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               jp   i_sbc

i_sbc_ax:      ld   a,(de)          ; SBC $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               jp   i_sbc

i_sbc_iy:      ld   a,(de)          ; SBC ($nn),Y
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               adc  a,h
               sub  l
               ld   h,a
               jp   i_sbc

i_sbc_i:       ld   h,d
               ld   l,e
               inc  de
i_sbc:         ex   af,af'          ; carry
               ccf                  ; uses inverted carry
               ld   a,b
               sbc  a,(hl)          ; A-M-(1-C)
sbc_daa:       nop
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               ccf                  ; no carry for overflow
               exx
               jp   pe,adcsbc_v
               ld   e,%00000000
               exx
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop


i_and_ix:      ld   a,(de)          ; AND ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_z:       ld   a,(de)          ; AND $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_a:       ex   de,hl           ; AND $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_zx:      ld   a,(de)          ; AND $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_ay:      ld   a,(de)          ; AND $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_ax:      ld   a,(de)          ; AND $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_iy:      ld   a,(de)          ; AND ($nn),Y
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               adc  a,h
               sub  l
               ld   h,a
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_i:       ld   h,d
               ld   l,e
               inc  de
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop


i_eor_ix:      ld   a,(de)          ; EOR ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_z:       ld   a,(de)          ; EOR $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_a:       ex   de,hl           ; EOR $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_zx:      ld   a,(de)          ; EOR $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_ay:      ld   a,(de)          ; EOR $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_ax:      ld   a,(de)          ; EOR $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_iy:      ld   a,(de)          ; EOR ($nn),Y
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               adc  a,h
               sub  l
               ld   h,a
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_i:       ld   h,d
               ld   l,e
               inc  de
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop


i_ora_ix:      ld   a,(de)          ; ORA ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_z:       ld   a,(de)          ; ORA $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_a:       ex   de,hl           ; ORA $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_zx:      ld   a,(de)          ; ORA $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_ay:      ld   a,(de)          ; ORA $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_ax:      ld   a,(de)          ; ORA $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_iy:      ld   a,(de)          ; ORA ($nn),Y
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               adc  a,h
               sub  l
               ld   h,a
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_i:       ld   h,d
               ld   l,e
               inc  de
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop


i_cmp_ix:      ld   a,(de)          ; CMP ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_z:       ld   a,(de)          ; CMP $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_a:       ex   de,hl           ; CMP $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_zx:      ld   a,(de)          ; CMP $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_ay:      ld   a,(de)          ; CMP $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_ax:      ld   a,(de)          ; CMP $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_iy:      ld   a,(de)          ; CMP ($nn),Y
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               adc  a,h
               sub  l
               ld   h,a
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_i:       ld   h,d
               ld   l,e
               inc  de
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop


i_cpx_z:       ld   a,(de)          ; CPX $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ex   af,af'          ; carry
               ld   a,iyh           ; X
               sub  (hl)            ; X-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cpx_a:       ex   de,hl           ; CPX $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'          ; carry
               ld   a,iyh           ; X
               sub  (hl)            ; X-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cpx_i:       ld   h,d
               ld   l,e
               inc  de
               ex   af,af'          ; carry
               ld   a,iyh           ; X
               sub  (hl)            ; X-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop


i_cpy_z:       ld   a,(de)          ; CPY $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ex   af,af'          ; carry
               ld   a,iyl           ; Y
               sub  (hl)            ; Y-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cpy_a:       ex   de,hl           ; CPY $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'          ; carry
               ld   a,iyl           ; Y
               sub  (hl)            ; Y-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cpy_i:       ld   h,d
               ld   l,e
               inc  de
               ex   af,af'          ; carry
               ld   a,iyl           ; Y
               sub  (hl)            ; Y-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop


i_dec_z:       ld   a,(de)          ; DEC $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               dec  (hl)            ; zero-page--
               ld   c,(hl)          ; set N Z
               jp   (ix) ; zread_write_loop

i_dec_zx:      ld   a,(de)          ; DEC $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               dec  (hl)            ; zero-page--
               ld   c,(hl)          ; set N Z
               jp   (ix) ; zread_write_loop

i_dec_a:       ex   de,hl           ; DEC $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               dec  (hl)            ; mem--
               ld   c,(hl)          ; set N Z
               jp   read_write_loop

i_dec_ax:      ld   a,(de)          ; DEC $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               dec  (hl)            ; mem--
               ld   c,(hl)          ; set N Z
               jp   read_write_loop


i_inc_z:       ld   a,(de)          ; INC $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               inc  (hl)            ; zero-page++
               ld   c,(hl)          ; set N Z
               jp   (ix) ; zread_write_loop

i_inc_zx:      ld   a,(de)          ; INC $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               inc  (hl)            ; zero-page++
               ld   c,(hl)          ; set N Z
               jp   (ix) ; zread_write_loop

i_inc_a:       ex   de,hl           ; INC $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               inc  (hl)            ; mem++
               ld   c,(hl)          ; set N Z
               jp   read_write_loop

i_inc_ax:      ld   a,(de)          ; INC $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               inc  (hl)            ; mem++
               ld   c,(hl)          ; set N Z
               jp   read_write_loop


i_asl_z:       ld   a,(de)          ; ASL $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ex   af,af'
               sla  (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_asl_zx:      ld   a,(de)          ; ASL $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ex   af,af'
               sla  (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_asl_a:       ex   de,hl           ; ASL $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'
               sla  (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_asl_ax:      ld   a,(de)          ; ASL $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ex   af,af'
               sla  (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_asl_acc:     ex   af,af'
               sla  b               ; A << 1
               ld   c,b             ; set N Z
               ex   af,af'          ; set carry
               jp   (ix)


i_lsr_z:       ld   a,(de)          ; LSR $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ex   af,af'
               srl  (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_lsr_zx:      ld   a,(de)          ; LSR $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ex   af,af'
               srl  (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_lsr_a:       ex   de,hl           ; LSR $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'
               srl  (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_lsr_ax:      ld   a,(de)          ; LSR $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ex   af,af'
               srl  (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_lsr_acc:     ex   af,af'
               srl  b               ; A >> 1
               ld   c,b             ; set N Z
               ex   af,af'          ; set carry
               jp   (ix)


i_rol_z:       ld   a,(de)          ; ROL $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ex   af,af'
               rl   (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_rol_zx:      ld   a,(de)          ; ROL $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ex   af,af'
               rl   (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_rol_a:       ex   de,hl           ; ROL $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'
               rl   (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_rol_ax:      ld   a,(de)          ; ROL $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ex   af,af'
               rl   (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_rol_acc:     ex   af,af'
               rl   b
               ld   c,b             ; set N Z
               ex   af,af'          ; set carry
               jp   (ix)


i_ror_z:       ld   a,(de)          ; ROR $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               ex   af,af'
               rr   (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_ror_zx:      ld   a,(de)          ; ROR $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               ex   af,af'
               rr   (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_ror_a:       ex   de,hl           ; ROR $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'
               rr   (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_ror_ax:      ld   a,(de)          ; ROR $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ex   af,af'
               rr   (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_ror_acc:     ex   af,af'
               rr   b
               ld   c,b             ; set N Z
               ex   af,af'          ; set carry
               jp   (ix)


i_bit_z:       ld   a,(de)          ; BIT $nn
               inc  de
               ld   l,a
               ld   h,zero_page_msb
               jp   i_bit

i_bit_zx:      ld   a,(de)          ; BIT $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,zero_page_msb
               jp   i_bit

i_bit_a:       ex   de,hl           ; BIT $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               jp   i_bit

i_bit_ax:      ld   a,(de)          ; BIT $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               jp   i_bit

i_bit_i:       ld   h,d             ; BIT #$nn
               ld   l,e
               inc  de
i_bit:         ld   c,(hl)          ; x
               ld   a,c
               and  %01000000       ; V flag from bit 6 of x
               exx
               ld   e,a             ; set V
               exx
               ld   a,(de)
               and  %11011111
               cp   0xd0             ; BNE or BEQ next?
               jr   z,bit_setz
               ld   c,(hl)          ; set N
               jp   (ix) ; read_loop
bit_setz:      ld   a,b             ; A
               and  c               ; perform BIT test
               ld   c,a             ; set Z
               jp   (ix) ; read_loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SECTION C64_CIA1
               defs 16             ; CIA #1 (keyboard, joystick, mouse, tape, IRQ)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SID interface functions

sid_clear:      ld c, rc2014_sid_port
                ld b, 0x98
                xor a
                out (c), a
                nop
                nop
                nop
                res 7,b
                out (c), a
                nop
                nop
                nop
                set 7,b
                out (c), a
                ret

; entry:
;        A = SID register (0x00 - 0x18)
;        D = DATA BYTE
;        E = interrup controller mode
;            (0x00 = off, 0x20 = 50Hz, 0x40 = 60Hz, 0x60 - 100Hx)

sid_io:         ld c, rc2014_sid_port
                or e
                ld b,a
                out (c), d
                nop
                nop
                nop
                set 7,b
                out (c), d
                ret



sid_reset:     ld   hl,last_regs
               ld   bc,rc2014_sid_port
               ld   d,b            ; write 0 to all registers
               ld   a,25           ; 25 registers to write
reset_loop:
               ld e, 0x00          ; interrupts off
               push bc
               push af
               call sid_io
               pop af
               pop bc

               inc  hl
               inc  b
               cp   b
               jr   nz,reset_loop  ; loop until all reset

               xor  a
               ld   (last_regs+0x04),a   ; control for voice 1
               ld   (last_regs+0x0b),a   ; control for voice 2
               ld   (last_regs+0x12),a   ; control for voice 3
               ret

sid_update:    ex   de,hl          ; switch new values to DE

               ld   hl,25          ; control 1 changes offset
               add  hl,de
               ld   a,(hl)         ; fetch changes
               and  a
               jr   z,control2     ; skip if nothing changed
               ld   (hl),0         ; reset changes for next time
               ld   hl,0x04         ; new register 4 offset
               ld   b,l            ; SID register 4
               add  hl,de
               xor  (hl)           ; toggle changed bits

               ld   (last_regs+0x04),a ; update last reg value

               push de
               ld d, a
               ld a, (quazar_int)
               ld e, a
               ld a, b
               call sid_io
               pop de

control2:      ld   hl,26          ; control 2 changes offset
               add  hl,de
               ld   a,(hl)
               and  a
               jr   z,control3     ; skip if no changes
               ld   (hl),0
               ld   hl,0x0b
               ld   b,l            ; SID register 11
               add  hl,de
               xor  (hl)
               ld   (last_regs+0x0b),a

               push de
               ld d, a
               ld a, (quazar_int)
               ld e, a
               ld a, b
               call sid_io
               pop de

control3:      ld   hl,27          ; control 3 changes offset
               add  hl,de
               ld   a,(hl)
               and  a
               jr   z,control_done ; skip if no changes
               ld   (hl),0
               ld   hl,0x12
               ld   b,l            ;  SID register 18
               add  hl,de
               xor  (hl)
               ld   (last_regs+0x12),a

               push de
               ld d, a
               ld a, (quazar_int)
               ld e, a
               ld a, b
               call sid_io
               pop de

control_done:  ld   hl,last_regs   ; previous register values
               ld   b,0            ; start with register 0
out_loop:      ld   a,(de)         ; new register value
               cp   (hl)           ; compare with previous value
               jr   z,sid_skip     ; skip if no change

               push bc
               push de
               ld d, a
               ld a, (quazar_int)
               ld e, a
               ld a, b
               call sid_io
               pop de
               pop bc

sid_skip:      inc  hl
               inc  de
               inc  b              ; next register
               ld   a,b
               cp   25             ; 25 registers to write
               jr   nz,out_loop    ; loop until all updated
               ld   hl,7
               add  hl,de          ; make up to a block of 32
               ret


; Set playback speed, using timer first then ntsc flag
check_speed:   ld   hl,(c64_cia_timer) ; C64 CIA#1 timer frequency
               ld   a,h
               or   l
               ret  z               ; accept 50Hz and 60Hz

; 985248.4Hz / HL = playback frequency in Hz
use_timer:     ld   a,h
               cp   0x3b             ; 65Hz
               jr   c,bad_timer     ; reject 65<freq<90hz
               cp   0x45             ; 55Hz
               ret  c               ; use 50Hz for 55-65Hz (compromise!)
               cp   0x56             ; 45Hz
               ret  c               ; use 50Hz for 45-55Hz
                                    ; reject <45Hz
bad_timer:     pop  hl              ; junk return address
               ld   a,ret_timer     ; unsupported frequency
               ret


SECTION C64_CIA2
               defs 16              ; CIA #2 (serial, NMI)

               defs 32              ; small private stack
defc new_stack =  $

blocks:        defw 0               ; buffered block count
head:          defw 0               ; head for recorded data
tail:          defw 0               ; tail for playing data

init_addr:     defw 0
play_addr:     defw 0
play_song:     defb 0
ntsc_tune:     defb 0               ; non-zero for 60Hz tunes
quazar_int:    defb 0x20

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Buffer management

record_block:  ld   de,(head)

               ld a, 0x08
               out (rc2014_dbg_port), a


               ld   hl,sid_regs     ; record from live SID values
               ld   bc,25           ; 25 registers to copy
               ldir
               ld   l,0x24           ; changes for control 1
               ldi
               ld   l,0x2b           ; changes for control 2
               ldi
               ld   l,0x32           ; changes for control 3
               ldi
               xor  a
               ld   l,0x24
               ld   (hl),a          ; clear control changes 1
               ld   l,0x2b
               ld   (hl),a          ; clear control changes 2
               ld   l,0x32
               ld   (hl),a          ; clear control changes 3
               inc  e
               inc  e
               inc  e
               inc  de              ; top up to 32 byte block
               res  4,d             ; wrap B000 back to A000
               ld   (head),de

               ld   hl,sid_regs
               ld   de,prev_regs
               ld   bc,25
               ldir

               ld   a,i             ; preserve iff1 to restore below
               di                   ; critical section for int handler
               ld   hl,(blocks)
               inc  hl
               ld   (blocks),hl
               ret  po
               ei
               ret

play_block:    ld   hl,(blocks)
               ld   a,h
               or   l
               ret  z

               ld a, 0x04
               out (rc2014_dbg_port), a

               ld   hl,(tail)
               call sid_update
               res  4,h             ; wrap from B000 back to A000
               ld   (tail),hl

               ld   hl,(blocks)
               dec  hl              ; consumed 1 block
               ld   (blocks),hl

               ret

enable_player: ld   hl,im2_table
               ld   c,im2_vector/256
im2_lp:        ld   (hl),c
               inc  l
               jr   nz,im2_lp       ; loop for first 256 entries
               ld   a,h
               inc  h
               ld   (hl),c          ; 257th entry
               im   2               ; set interrupt mode 2
               ld   i,a

               ld a, (quazar_int)   ; enable interrupts
               ld e, a
               ld a, 0
               ld d, 0
               call sid_io

               ld a, 0x02
               out (rc2014_dbg_port), a

               ei                   ; enable player
               ret


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SECTION VECTOR

im2_vector:    jp   im2_handler     ; interrupt mode 2 handler

; Reordering the decode table to group low and high bytes avoids
; 16-bit arithmetic for the decode stage, saving 12T

defc reorder_256 =  im2_table       ; use IM2 table as working space

reorder_decode:ld   hl,decode_table
               ld   d,h
               ld   e,l
               ld   bc,reorder_256  ; 256-byte temporary store
reorder_lp:    ld   a,(hl)          ; low byte
               ld   (de),a
               inc  l
               inc  e
               ld   a,(hl)          ; high byte
               ld   (bc),a
               inc  hl
               inc  c
               jr   nz,reorder_lp
               dec  h               ; back to 2nd half (high bytes)
reorder_lp2:   ld   a,(bc)
               ld   (hl),a
               inc  c
               inc  l
               jr   nz,reorder_lp2
               ld   a,z80_ret_op
               ld   (reorder_decode),a ; this is a one-time operation
               ret



SECTION DECODE

decode_table:  defw i_brk,i_ora_ix,i_undoc_1,i_undoc_2     ; 00
               defw i_undoc_1,i_ora_z,i_asl_z,i_undoc_2    ; 04
               defw i_php,i_ora_i,i_asl_acc,i_undoc_2      ; 08
               defw i_undoc_3,i_ora_a,i_asl_a,i_undoc_2    ; 0C

               defw i_bpl,i_ora_iy,i_undoc_2,i_undoc_2     ; 10
               defw i_undoc_1,i_ora_zx,i_asl_zx,i_undoc_2  ; 14
               defw i_clc,i_ora_ay,i_undoc_1,i_undoc_3     ; 18
               defw i_undoc_3,i_ora_ax,i_asl_ax,i_undoc_2  ; 1C

               defw i_jsr,i_and_ix,i_undoc_1,i_undoc_2     ; 20
               defw i_bit_z,i_and_z,i_rol_z,i_undoc_2      ; 24
               defw i_plp,i_and_i,i_rol_acc,i_undoc_2      ; 28
               defw i_bit_a,i_and_a,i_rol_a,i_undoc_2      ; 2C

               defw i_bmi,i_and_iy,i_undoc_2,i_undoc_2     ; 30
               defw i_bit_zx,i_and_zx,i_rol_zx,i_undoc_2   ; 34
               defw i_sec,i_and_ay,i_undoc_1,i_undoc_3     ; 38
               defw i_bit_ax,i_and_ax,i_rol_ax,i_undoc_2   ; 3C

               defw i_rti,i_eor_ix,i_undoc_1,i_undoc_2     ; 40
               defw i_undoc_2,i_eor_z,i_lsr_z,i_undoc_2    ; 44
               defw i_pha,i_eor_i,i_lsr_acc,i_undoc_2      ; 48
               defw i_jmp_a,i_eor_a,i_lsr_a,i_undoc_2      ; 4C

               defw i_bvc,i_eor_iy,i_undoc_2,i_undoc_2     ; 50
               defw i_undoc_2,i_eor_zx,i_lsr_zx,i_undoc_2  ; 54
               defw i_cli,i_eor_ay,i_undoc_1,i_undoc_3     ; 58
               defw i_undoc_3,i_eor_ax,i_lsr_ax,i_undoc_2  ; 5C

               defw i_rts,i_adc_ix,i_undoc_1,i_undoc_2     ; 60
               defw i_undoc_2,i_adc_z,i_ror_z,i_undoc_2    ; 64
               defw i_pla,i_adc_i,i_ror_acc,i_undoc_2      ; 68
               defw i_jmp_i,i_adc_a,i_ror_a,i_undoc_2      ; 6C

               defw i_bvs,i_adc_iy,i_undoc_2,i_undoc_2     ; 70
               defw i_stz_zx,i_adc_zx,i_ror_zx,i_undoc_2   ; 74
               defw i_sei,i_adc_ay,i_undoc_1,i_undoc_3     ; 78
               defw i_undoc_3,i_adc_ax,i_ror_ax,i_undoc_2  ; 7C

               defw i_undoc_2,i_sta_ix,i_undoc_2,i_undoc_2 ; 80
               defw i_sty_z,i_sta_z,i_stx_z,i_undoc_2      ; 84
               defw i_dey,i_bit_i,i_txa,i_undoc_2          ; 88
               defw i_sty_a,i_sta_a,i_stx_a,i_undoc_2      ; 8C

               defw i_bcc,i_sta_iy,i_undoc_2,i_undoc_2     ; 90
               defw i_sty_zx,i_sta_zx,i_stx_zy,i_undoc_2   ; 94
               defw i_tya,i_sta_ay,i_txs,i_undoc_2         ; 98
               defw i_stz_a,i_sta_ax,i_stz_ax,i_undoc_2    ; 9C

               defw i_ldy_i,i_lda_ix,i_ldx_i,i_undoc_2     ; A0
               defw i_ldy_z,i_lda_z,i_ldx_z,i_undoc_2      ; A4
               defw i_tay,i_lda_i,i_tax,i_undoc_2          ; A8
               defw i_ldy_a,i_lda_a,i_ldx_a,i_undoc_2      ; AC

               defw i_bcs,i_lda_iy,i_undoc_2,i_undoc_2     ; B0
               defw i_ldy_zx,i_lda_zx,i_ldx_zy,i_undoc_2   ; B4
               defw i_clv,i_lda_ay,i_tsx,i_undoc_3         ; B8
               defw i_ldy_ax,i_lda_ax,i_ldx_ay,i_undoc_2   ; BC

               defw i_cpy_i,i_cmp_ix,i_undoc_2,i_undoc_2   ; C0
               defw i_cpy_z,i_cmp_z,i_dec_z,i_undoc_2      ; C4
               defw i_iny,i_cmp_i,i_dex,i_undoc_1          ; C8
               defw i_cpy_a,i_cmp_a,i_dec_a,i_undoc_2      ; CC

               defw i_bne,i_cmp_iy,i_undoc_2,i_undoc_2     ; D0
               defw i_undoc_2,i_cmp_zx,i_dec_zx,i_undoc_2  ; D4
               defw i_cld,i_cmp_ay,i_undoc_1,i_undoc_1     ; D8
               defw i_undoc_3,i_cmp_ax,i_dec_ax,i_undoc_2  ; DC

               defw i_cpx_i,i_sbc_ix,i_undoc_2,i_undoc_2   ; E0
               defw i_cpx_z,i_sbc_z,i_inc_z,i_undoc_2      ; E4
               defw i_inx,i_sbc_i,i_nop,i_undoc_2          ; E8
               defw i_cpx_a,i_sbc_a,i_inc_a,i_undoc_2      ; EC

               defw i_beq,i_sbc_iy,i_undoc_2,i_undoc_2     ; F0
               defw i_undoc_2,i_sbc_zx,i_inc_zx,i_undoc_2  ; F4
               defw i_sed,i_sbc_ay,i_undoc_1,i_undoc_3     ; F8
               defw i_undoc_3,i_sbc_ax,i_inc_ax,i_undoc_2  ; FC

; :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

