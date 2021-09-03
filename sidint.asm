

PUBLIC _main
SECTIOn code_user

_main:
	di
	im 1

	ld a, 0xfb
	ld (0x38),a
	ld a, 0xc9
	ld (0x39),a

	ld c, 0x54
	ld b, 0x98
	xor a
	out (c),a
	nop
	nop
	nop
	res 7,b
	out (c),a
	nop
	nop
	nop
	set 7,b
	out (c),a

	ld a,0
	ld b,0x20
	ld c,0x54
	out (c),a
	ei

loop:
	ld a, (ledval)
	out (0x00), a
	inc a
	ld (ledval), a
	halt

	jr loop

ledval:
	defb 0x01
	
