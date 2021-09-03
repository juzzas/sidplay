

PUBLIC _main
SECTION code_user

EXTERN standalone_sid_file_base
EXTERN standalone_sid_file_length

EXTERN sidplay_loader

DEFC sidplay_start = 0xd000

_main:
	di

	call sidplay_loader

	ld hl, standalone_sid_file_base
	ld de, standalone_sid_file_length

	call sidplay_start

	; display return value
	ld a, c
	out (0x00), a

	ret

loop:
	ld a, (ledval)
	out (0x00), a
	inc a
	ld (ledval), a
	ret

ledval:
	defb 0x01
	
